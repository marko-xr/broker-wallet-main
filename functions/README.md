# Cloud Functions - Quota System

This directory contains Firebase Cloud Functions that enforce server-side quota limits for the Broker Wallet application.

## Functions Overview

### `addItemWithQuota`
Callable Cloud Function that creates items with server-side quota enforcement.

**Type:** `onCall` (v2 HTTPS Callable)  
**Region:** us-central1  
**Timeout:** 60 seconds  
**Memory:** 512MiB  

## Setup

### Prerequisites
- Node.js 18 or later
- Firebase CLI (`npm install -g firebase-tools`)
- Firebase project with Firestore and Cloud Functions enabled

### Installation
```bash
cd functions
npm install
```

### Environment Configuration
```bash
# Login to Firebase
firebase login

# Set active project
firebase use <your-project-id>
```

### Deploy
```bash
# Deploy single function
firebase deploy --only functions:addItemWithQuota

# Deploy all functions
firebase deploy --only functions
```

## Function Details

### Request Schema
```typescript
{
  section: string,              // One of: offers, requests, owners, offices, tools, quotations
  payload: object,              // Item data (without reserved fields)
  idempotencyToken: string      // UUID v4 (minimum 20 characters)
}
```

### Response Schema
```typescript
{
  itemId: string,               // ID of created item
  section: string,              // Section where item was created
  currentCount: number | null,  // New count after creation
  quotaLimit: number | null,    // Quota limit (null for premium)
  replayed: boolean             // True if idempotent replay
}
```

### Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `unauthenticated` | User not signed in | Redirect to login |
| `invalid-argument` | Bad section or token | Fix client request |
| `failed-precondition` | User profile missing | Complete account setup |
| `resource-exhausted` | Quota limit reached | Show upgrade dialog |
| `internal` | Unexpected error | Retry or contact support |

## Testing

### Unit Tests
```bash
cd functions
npm test
```

### Integration Tests with Emulator
```bash
# Terminal 1: Start emulators
firebase emulators:start

# Terminal 2: Run tests
npm run test:integration
```

### Manual Testing
```bash
# Start emulators
firebase emulators:start

# In Firebase Emulator UI (http://localhost:4000):
# 1. Create test user in Authentication
# 2. Add user document in Firestore with plan="free"
# 3. Use Functions tab to call addItemWithQuota
```

## Monitoring

### View Logs
```bash
# Real-time logs
firebase functions:log --only addItemWithQuota --tail

# Recent logs
firebase functions:log --only addItemWithQuota --limit 100
```

### Cloud Console
https://console.cloud.google.com/functions/list

### Metrics
- Invocations per minute
- Error rate
- Execution time (p50, p95, p99)
- Memory usage

## Quota Limits

### Free Plan
- 5 items per section
- Sections: offers, requests, owners, offices, tools, quotations
- Total: 30 items across all sections

### Premium Plan
- Unlimited items
- All features unlocked

## Security

### Authentication
- Requires valid Firebase Auth token
- Extracts `uid` from `request.auth`
- Anonymous users blocked

### Authorization
- Users can only create items in their own collection
- Items tagged with `ownerId` = authenticated uid
- Server validates all inputs

### Input Sanitization
Forbidden fields automatically removed from payload:
- `ownerId`
- `section`
- `createdAt`
- `updatedAt`
- `id`
- `counts`
- `userId`

### Idempotency
- UUID token required for all requests
- Tokens stored in `users/{uid}/idempotency_tokens/{token}`
- Replays return cached result
- Prevents duplicate items from retries

## Performance

### Cold Start
- First invocation: ~2-5 seconds
- Subsequent: <500ms
- Consider minimum instances for critical functions

### Throughput
- Max concurrent: 10 instances (configurable)
- ~100 requests/second with proper scaling
- Transactions handle concurrency safely

### Optimization Tips
1. Use minimum instances to reduce cold starts
2. Increase memory for faster CPU
3. Enable HTTP/2 for better performance
4. Use Cloud Functions v2 (already implemented)

## Troubleshooting

### "Function not found"
```bash
# Verify deployment
firebase functions:list

# Redeploy
firebase deploy --only functions:addItemWithQuota
```

### "Permission denied"
Check Firestore rules allow server writes:
```javascript
// Should have special handling for server writes
// Or use Admin SDK (bypasses rules)
```

### "Transaction aborted"
- High concurrency causing conflicts
- Add exponential backoff retries
- Reduce transaction scope

### "Timeout"
- Increase timeout in function config
- Optimize Firestore queries
- Check for slow external API calls

## Cost Optimization

### Current Configuration
- Region: us-central1 (cheapest)
- Memory: 512MiB (balanced)
- Timeout: 60s (generous)
- Max instances: 10 (prevents runaway costs)

### Pricing Estimate (as of 2025)
- Invocations: $0.40 per million
- Compute time: $0.0000025 per GB-second
- Networking: $0.12 per GB

**Example:** 1M invocations/month @ 500ms each = ~$2/month

### Cost Reduction Tips
1. Optimize function execution time
2. Use appropriate memory allocation
3. Set max instances based on traffic
4. Enable billing alerts
5. Monitor unused functions

## Backup & Disaster Recovery

### Backup Strategy
1. Git version control (code)
2. Firestore automated backups (data)
3. Audit logs exported to BigQuery

### Recovery Process
1. Rollback to previous Git commit
2. Redeploy functions: `firebase deploy --only functions`
3. Restore Firestore from backup if needed
4. Verify with smoke tests

## Support

### Documentation
- [Firebase Cloud Functions Docs](https://firebase.google.com/docs/functions)
- [Cloud Functions Best Practices](https://firebase.google.com/docs/functions/best-practices)
- [Firestore Transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)

### Getting Help
1. Check logs: `firebase functions:log`
2. Review audit logs in Firestore
3. Check Firebase Console > Functions
4. Contact Firebase Support

## Development

### Local Development
```bash
# Start emulators
firebase emulators:start

# Functions UI: http://localhost:4001
# Firestore UI: http://localhost:4000
```

### Adding New Functions
1. Create function in `index.js` or separate file
2. Export in `index.js`
3. Deploy: `firebase deploy --only functions:newFunction`
4. Update Firestore rules if needed
5. Add client SDK calls
6. Test thoroughly
7. Document in this README

### Code Style
- Use `'use strict';`
- ESLint with Google style guide
- JSDoc comments for public functions
- Async/await preferred over promises
- Use const/let, avoid var

### Git Workflow
1. Create feature branch
2. Make changes
3. Run `npm test` and `npm run lint`
4. Commit with descriptive message
5. Push and create PR
6. Deploy after approval

## Changelog

### Version 1.0.0 (2025-10-21)
- Initial implementation of `addItemWithQuota`
- Server-side quota enforcement (5 for free, unlimited for premium)
- Idempotency support with UUID tokens
- Audit logging for all operations
- Transaction-based atomic operations
- Comprehensive error handling

### Future Enhancements
- [ ] `deleteItemWithQuota` - decrement counts on delete
- [ ] `updateItemQuota` - admin function to adjust quotas
- [ ] `getQuotaStatus` - fetch quota info without creating item
- [ ] Rate limiting per user
- [ ] Usage analytics and reporting
- [ ] Scheduled cleanup of old idempotency tokens
