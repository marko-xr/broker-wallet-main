const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { TranscoderServiceClient } = require('@google-cloud/video-transcoder');

// Initialize Firebase Admin if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const transcoderClient = new TranscoderServiceClient();
const PROJECT_ID = process.env.GCLOUD_PROJECT;
const LOCATION = 'australia-southeast1';

/**
 * Cloud Function to initiate HLS transcoding for uploaded videos
 * Creates adaptive streaming versions for optimal playback across devices
 */
exports.transcodeToHLS = functions.https.onRequest({
  region: 'australia-southeast1',
  maxInstances: 10,
  timeoutSeconds: 540, // 9 minutes
  memory: '1GiB',
  cors: true,
}, async (req, res) => {
  try {
    console.log('🎬 Starting HLS transcoding request');
    
    // Validate request method
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Method not allowed' });
    }

    // Extract request parameters
    const {
      videoPath,
      outputBucket,
      region = 'australia-southeast1',
      qualities = ['low', 'medium', 'high'],
      metadata = {}
    } = req.body;

    // Validate required parameters
    if (!videoPath || !outputBucket) {
      return res.status(400).json({ 
        error: 'Missing required parameters: videoPath, outputBucket' 
      });
    }

    console.log(`📹 Processing video: ${videoPath}`);
    console.log(`📦 Output bucket: ${outputBucket}`);

    // Generate unique job ID
    const jobId = `hls_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const outputPath = `hls/${jobId}`;

    // Create transcoding job configuration
    const jobConfig = createHLSJobConfig({
      videoPath,
      outputBucket,
      outputPath,
      qualities,
      jobId
    });

    // Submit transcoding job to Google Cloud Transcoder API
    const [operation] = await transcoderClient.createJob({
      parent: transcoderClient.locationPath(PROJECT_ID, LOCATION),
      job: jobConfig,
    });

    console.log(`✅ Transcoding job created: ${jobId}`);
    console.log(`🔄 Operation name: ${operation.name}`);

    // Store job metadata in Firestore
    await admin.firestore().collection('transcoding_jobs').doc(jobId).set({
      jobId,
      videoPath,
      outputBucket,
      outputPath,
      qualities,
      status: 'created',
      operationName: operation.name,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      estimatedDurationSeconds: estimateTranscodingDuration(videoPath),
      metadata,
    });

    // Return job information
    res.status(200).json({
      jobId,
      status: 'created',
      videoPath,
      outputBucket,
      outputPath,
      operationName: operation.name,
      estimatedDuration: estimateTranscodingDuration(videoPath),
      hlsBaseUrl: `https://storage.googleapis.com/${outputBucket}/${outputPath}`,
    });

  } catch (error) {
    console.error('❌ Transcoding request failed:', error);
    res.status(500).json({ 
      error: 'Transcoding request failed', 
      details: error.message 
    });
  }
});

/**
 * Cloud Function to check transcoding job status
 */
exports.getTranscodingStatus = functions.https.onRequest({
  region: 'australia-southeast1',
  maxInstances: 10,
  timeoutSeconds: 60,
  memory: '256MiB',
  cors: true,
}, async (req, res) => {
  try {
    const { jobId } = req.query;

    if (!jobId) {
      return res.status(400).json({ error: 'Missing jobId parameter' });
    }

    console.log(`📊 Checking status for job: ${jobId}`);

    // Get job metadata from Firestore
    const jobDoc = await admin.firestore().collection('transcoding_jobs').doc(jobId).get();
    
    if (!jobDoc.exists) {
      return res.status(404).json({ error: 'Job not found' });
    }

    const jobData = jobDoc.data();
    const { operationName, outputBucket, outputPath } = jobData;

    // Check operation status with Google Cloud Transcoder API
    let operationStatus = 'processing';
    let progressPercent = 50;
    let currentStep = 'Transcoding in progress';
    let hlsUrl = null;
    let thumbnailUrl = null;

    try {
      const [operation] = await transcoderClient.checkCreateJobProgress(operationName);
      
      if (operation.done) {
        if (operation.error) {
          operationStatus = 'failed';
          currentStep = `Error: ${operation.error.message}`;
          progressPercent = 0;
        } else {
          operationStatus = 'succeeded';
          currentStep = 'Transcoding completed';
          progressPercent = 100;
          
          // Generate output URLs
          hlsUrl = `https://storage.googleapis.com/${outputBucket}/${outputPath}/master.m3u8`;
          thumbnailUrl = `https://storage.googleapis.com/${outputBucket}/${outputPath}/thumbnails/thumbnail_0.jpg`;
        }
      } else {
        // Estimate progress based on elapsed time
        const createdAt = jobData.createdAt?.toDate() || new Date();
        const elapsed = Date.now() - createdAt.getTime();
        const estimated = jobData.estimatedDurationSeconds * 1000;
        progressPercent = Math.min(90, Math.round((elapsed / estimated) * 100));
      }
    } catch (opError) {
      console.warn('⚠️ Could not check operation status:', opError.message);
      // Continue with estimated progress
    }

    // Update job status in Firestore
    await admin.firestore().collection('transcoding_jobs').doc(jobId).update({
      status: operationStatus,
      progressPercent,
      currentStep,
      hlsUrl,
      thumbnailUrl,
      lastChecked: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(200).json({
      jobId,
      state: operationStatus,
      progressPercent,
      currentStep,
      estimatedTimeRemaining: operationStatus === 'processing' 
        ? Math.max(0, (jobData.estimatedDurationSeconds * 1000) - (Date.now() - (jobData.createdAt?.toDate()?.getTime() || Date.now())))
        : 0,
      hlsUrl,
      thumbnailUrl,
    });

  } catch (error) {
    console.error('❌ Status check failed:', error);
    res.status(500).json({ 
      error: 'Status check failed', 
      details: error.message 
    });
  }
});

/**
 * Cloud Function to clean up transcoding artifacts
 */
exports.cleanupTranscodingJob = functions.https.onRequest({
  region: 'australia-southeast1',
  maxInstances: 5,
  timeoutSeconds: 300,
  memory: '256MiB',
  cors: true,
}, async (req, res) => {
  try {
    const { jobId } = req.body;

    if (!jobId) {
      return res.status(400).json({ error: 'Missing jobId parameter' });
    }

    console.log(`🗑️ Cleaning up transcoding job: ${jobId}`);

    // Get job metadata
    const jobDoc = await admin.firestore().collection('transcoding_jobs').doc(jobId).get();
    
    if (!jobDoc.exists) {
      return res.status(404).json({ error: 'Job not found' });
    }

    const { outputBucket, outputPath } = jobDoc.data();

    // Delete transcoded files from Storage
    try {
      const bucket = admin.storage().bucket(outputBucket);
      await bucket.deleteFiles({ prefix: outputPath });
      console.log(`✅ Deleted files with prefix: ${outputPath}`);
    } catch (storageError) {
      console.warn('⚠️ Storage cleanup failed:', storageError.message);
    }

    // Delete job metadata from Firestore
    await admin.firestore().collection('transcoding_jobs').doc(jobId).delete();

    res.status(200).json({ 
      message: 'Cleanup completed',
      jobId,
      deletedPath: outputPath 
    });

  } catch (error) {
    console.error('❌ Cleanup failed:', error);
    res.status(500).json({ 
      error: 'Cleanup failed', 
      details: error.message 
    });
  }
});

/**
 * Create HLS transcoding job configuration
 */
function createHLSJobConfig({ videoPath, outputBucket, outputPath, qualities, jobId }) {
  // Input configuration
  const inputUri = videoPath.startsWith('gs://') ? videoPath : `gs://${videoPath}`;
  const outputUri = `gs://${outputBucket}/${outputPath}/`;

  // Quality presets mapping
  const qualityPresets = {
    low: { height: 360, bitrate: 800000 },
    medium: { height: 720, bitrate: 2500000 },
    high: { height: 1080, bitrate: 5000000 },
    ultra: { height: 1440, bitrate: 8000000 },
  };

  // Create video streams for each quality
  const videoStreams = qualities.map((quality, index) => {
    const preset = qualityPresets[quality] || qualityPresets.medium;
    return {
      key: `video_${quality}`,
      h264: {
        heightPixels: preset.height,
        widthPixels: Math.round(preset.height * 16 / 9), // 16:9 aspect ratio
        bitrateBps: preset.bitrate,
        frameRate: 30,
        pixelFormat: 'yuv420p',
        rateControlMode: 'vbr',
        crfLevel: quality === 'low' ? 28 : quality === 'medium' ? 23 : 18,
        gopDuration: '2s',
        vbvSizeBits: preset.bitrate * 2,
        vbvFullnessBits: preset.bitrate * 1.5,
        entropyCoder: 'cabac',
        profile: 'high',
        preset: 'veryfast',
      },
    };
  });

  // Audio stream configuration
  const audioStream = {
    key: 'audio',
    aac: {
      bitrateBps: 128000,
      channelCount: 2,
      sampleRateHertz: 48000,
    },
  };

  // HLS manifest configurations
  const manifestConfigs = [
    {
      key: 'hls_manifest',
      fileName: 'master.m3u8',
      type: 'HLS',
      muxStreams: [
        ...qualities.map((quality) => ({
          key: `mux_${quality}`,
          container: 'ts',
          videoStream: { key: `video_${quality}` },
          audioStream: { key: 'audio' },
          segmentSettings: {
            segmentDuration: '6s',
            individualSegments: true,
          },
        })),
      ],
    },
  ];

  // Thumbnail generation (sprite sheet for seeking)
  const spriteSheets = [
    {
      format: 'jpeg',
      spriteWidthPixels: 128,
      spriteHeightPixels: 72,
      columnCount: 10,
      rowCount: 10,
      totalCount: 100,
      startTimeOffset: '0s',
      endTimeOffset: '100s',
      filePrefix: 'thumbnails/thumbnail',
    },
  ];

  return {
    inputUri,
    outputUri,
    config: {
      inputs: [{ key: 'input0', uri: inputUri }],
      editList: [{ key: 'atom0', inputs: ['input0'] }],
      elementaryStreams: [...videoStreams, audioStream],
      muxStreams: manifestConfigs[0].muxStreams,
      manifests: manifestConfigs,
      spriteSheets,
      pubsubTopic: `projects/${PROJECT_ID}/topics/transcoding-notifications`, // Optional
    },
    labels: {
      jobId,
      type: 'hls-transcoding',
      created: new Date().toISOString(),
    },
  };
}

/**
 * Estimate transcoding duration based on video file path/size
 */
function estimateTranscodingDuration(videoPath) {
  // Simple estimation: assume 1 minute of processing per minute of video
  // In reality, this would analyze video metadata
  
  // Default to 5 minutes for unknown videos
  let estimatedMinutes = 5;
  
  // Try to extract hints from filename
  if (videoPath.includes('short') || videoPath.includes('30s')) {
    estimatedMinutes = 1;
  } else if (videoPath.includes('long') || videoPath.includes('10m')) {
    estimatedMinutes = 15;
  }
  
  return estimatedMinutes * 60; // Convert to seconds
}

/**
 * Pub/Sub trigger for transcoding completion notifications
 */
exports.onTranscodingComplete = functions.pubsub.topic('transcoding-notifications')
  .onPublish(async (message) => {
    try {
      const notification = JSON.parse(message.data.toString());
      console.log('📧 Transcoding notification received:', notification);

      // Extract job information from the notification
      const jobId = notification.labels?.jobId;
      if (!jobId) {
        console.warn('⚠️ No jobId found in notification');
        return;
      }

      // Update job status in Firestore
      const status = notification.state === 'SUCCEEDED' ? 'succeeded' : 'failed';
      
      await admin.firestore().collection('transcoding_jobs').doc(jobId).update({
        status,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        finalNotification: notification,
      });

      // Optionally send push notification to user
      // await sendTranscodingCompleteNotification(jobId, status);

      console.log(`✅ Updated job ${jobId} status to ${status}`);

    } catch (error) {
      console.error('❌ Error processing transcoding notification:', error);
    }
  });

/**
 * Scheduled function to clean up old transcoding jobs
 */
exports.cleanupOldTranscodingJobs = functions.pubsub.schedule('0 2 * * *') // Daily at 2 AM
  .timeZone('Australia/Sydney')
  .onRun(async (context) => {
    try {
      console.log('🧹 Starting cleanup of old transcoding jobs');

      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - 7); // 7 days ago

      // Find old jobs
      const oldJobsQuery = await admin.firestore()
        .collection('transcoding_jobs')
        .where('createdAt', '<', cutoffDate)
        .limit(100)
        .get();

      console.log(`Found ${oldJobsQuery.size} old jobs to clean up`);

      // Delete old jobs in batches
      const batch = admin.firestore().batch();
      const deletionPromises = [];

      oldJobsQuery.docs.forEach((doc) => {
        const { outputBucket, outputPath } = doc.data();
        
        // Delete Firestore document
        batch.delete(doc.ref);
        
        // Delete Storage files
        deletionPromises.push(
          admin.storage().bucket(outputBucket).deleteFiles({ prefix: outputPath })
            .catch(error => console.warn(`⚠️ Failed to delete ${outputPath}:`, error.message))
        );
      });

      // Execute deletions
      await Promise.all([
        batch.commit(),
        ...deletionPromises,
      ]);

      console.log(`✅ Cleaned up ${oldJobsQuery.size} old transcoding jobs`);

    } catch (error) {
      console.error('❌ Cleanup job failed:', error);
    }
  });