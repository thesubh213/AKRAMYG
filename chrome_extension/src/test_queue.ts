// test_queue.ts - Extension Offline Queue Unit Test

// Simple local storage mock database
const storageMock: { [key: string]: any } = {};

// Mock chrome.storage.local
const chromeMock = {
  storage: {
    local: {
      get: async (keys: string | string[]) => {
        const result: { [key: string]: any } = {};
        if (typeof keys === 'string') {
          result[keys] = storageMock[keys];
        } else {
          keys.forEach(k => {
            result[k] = storageMock[k];
          });
        }
        return result;
      },
      set: async (items: { [key: string]: any }) => {
        Object.keys(items).forEach(k => {
          storageMock[k] = items[k];
        });
        return true;
      }
    }
  }
};

// Queue helper matching background.ts logic
async function queueEventMock(event: any) {
  const fullEvent = {
    ...event,
    id: Math.random().toString(36).substring(2, 9),
    timestamp: new Date().toISOString()
  };
  const data = await chromeMock.storage.local.get('eventQueue');
  const queue = data.eventQueue || [];
  queue.push(fullEvent);
  await chromeMock.storage.local.set({ eventQueue: queue });
  return true;
}

// Sync helper matching background.ts logic
async function syncEventsMock(mockFetchSucceeds: boolean): Promise<boolean> {
  const data = await chromeMock.storage.local.get('eventQueue');
  const queue = data.eventQueue || [];

  if (queue.length === 0) return true;

  try {
    // Mock network fetch
    if (!mockFetchSucceeds) {
      throw new Error('Network Unreachable');
    }

    // Success -> Clear queue
    await chromeMock.storage.local.set({ eventQueue: [] });
    return true;
  } catch (err) {
    // Failure -> Keep queue intact
    return false;
  }
}

// Simple test runner
async function runTests() {
  console.log('--- Starting Chrome Extension Queue Tests ---');
  
  // 1. Initial State
  storageMock['eventQueue'] = [];
  
  // 2. Queue some events
  await queueEventMock({ type: 'deadline', data: { title: 'Math Homework' } });
  await queueEventMock({ type: 'distraction', data: { domain: 'youtube.com' } });
  
  let data = await chromeMock.storage.local.get('eventQueue');
  let queue = data.eventQueue || [];
  
  if (queue.length === 2) {
    console.log('✅ PASS: Successfully queued 2 events.');
  } else {
    console.error('❌ FAIL: Expected 2 events, got ' + queue.length);
  }

  // 3. Test failed sync (offline)
  const syncOfflineResult = await syncEventsMock(false);
  data = await chromeMock.storage.local.get('eventQueue');
  queue = data.eventQueue || [];
  
  if (!syncOfflineResult && queue.length === 2) {
    console.log('✅ PASS: Offline sync correctly preserved queued events.');
  } else {
    console.error('❌ FAIL: Offline sync cleared or modified queue incorrectly.');
  }

  // 4. Test successful sync (online)
  const syncOnlineResult = await syncEventsMock(true);
  data = await chromeMock.storage.local.get('eventQueue');
  queue = data.eventQueue || [];
  
  if (syncOnlineResult && queue.length === 0) {
    console.log('✅ PASS: Online sync successfully cleared queue.');
  } else {
    console.error('❌ FAIL: Online sync failed or did not clear queue.');
  }

  console.log('--- Chrome Extension Queue Tests Completed ---');
}

runTests().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
