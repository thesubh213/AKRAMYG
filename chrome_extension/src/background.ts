// background.ts for AKRAMYG Chrome Extension

import { encryptPayload, deriveChannelId } from './crypto';

interface ExtensionConfig {
  androidIp: string;
  androidPort: string;
  syncIntervalMins: number;
  cloudRelayEnabled: boolean;
  cloudRelayUrl: string;
  cloudRelayPairingKey: string;
  distractionDomains?: string[];
}

interface QueuedEvent {
  id: string;
  timestamp: string;
  type: 'deadline' | 'entity' | 'research_session' | 'page_attach' | 'distraction';
  data: any;
}

interface AppStatus {
  isConnected: boolean;
  activeTaskId: string | null;
  activeTaskTitle: string | null;
  activeTaskDescription: string | null;
  pendingSubtasks: Array<{ id: string; title: string; order_index: number }> | null;
  isFocusSessionActive: boolean;
  lastSyncTime: string | null;
}

async function isBypassed(tabId: number, domain: string): Promise<boolean> {
  const result = await chrome.storage.local.get('bypassedTabs');
  const bypassed = result.bypassedTabs || {};
  return bypassed[tabId] === domain;
}

async function addBypass(tabId: number, domain: string) {
  const result = await chrome.storage.local.get('bypassedTabs');
  const bypassed = result.bypassedTabs || {};
  bypassed[tabId] = domain;
  await chrome.storage.local.set({ bypassedTabs: bypassed });
}

async function clearBypasses() {
  await chrome.storage.local.set({ bypassedTabs: {} });
}

async function completeSubtask(subtaskId: string): Promise<{ success: boolean; message: string }> {
  const config = await getConfig();
  const url = `http://${config.androidIp}:${config.androidPort}/complete-subtask`;
  console.log(`Completing subtask ${subtaskId} via Android Core at ${url}...`);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({ subtaskId })
    });

    if (response.ok) {
      await syncEventsWithAndroid();
      return { success: true, message: 'Subtask completed successfully.' };
    } else {
      throw new Error(`Server returned code ${response.status}`);
    }
  } catch (err) {
    console.error('Failed to complete subtask:', err);
    return { success: false, message: (err as Error).message };
  }
}

const DEFAULT_CONFIG: ExtensionConfig = {
  androidIp: '192.168.1.100', // Mock placeholder, user configures in popup
  androidPort: '8080',
  syncIntervalMins: 1,
  cloudRelayEnabled: false,
  cloudRelayUrl: 'http://192.168.1.100:8080/relay',
  cloudRelayPairingKey: '',
  distractionDomains: ['youtube.com', 'facebook.com', 'reddit.com', 'instagram.com', 'twitter.com', 'x.com', 'netflix.com'],
};

// Initialize alarm for sync loop
chrome.alarms.create('sync_alarm', { periodInMinutes: DEFAULT_CONFIG.syncIntervalMins });

// Alarm handler
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync_alarm') {
    syncEventsWithAndroid();
  }
});

// Watch tabs for context changes and distraction detection
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  checkTabContext(activeInfo.tabId);
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete') {
    checkTabContext(tabId);
  }
});

// Listener for message communication (from popup and content scripts)
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'ADD_EVENT') {
    queueEvent(message.event).then((success) => {
      sendResponse({ success });
      if (success) {
        // Attempt immediate sync
        syncEventsWithAndroid();
      }
    });
    return true; // Keep channel open for async response
  }

  if (message.action === 'UPDATE_CONFIG') {
    saveConfig(message.config).then((success) => {
      sendResponse({ success });
      // Re-create alarm with new sync interval
      chrome.alarms.clear('sync_alarm').then(() => {
        chrome.alarms.create('sync_alarm', { periodInMinutes: message.config.syncIntervalMins || 1 });
      });
      syncEventsWithAndroid(); // Sync immediately with new config
    });
    return true;
  }

  if (message.action === 'GET_STATUS') {
    getStatus().then(sendResponse);
    return true;
  }

  if (message.action === 'SYNC_NOW') {
    syncEventsWithAndroid().then((result) => {
      sendResponse(result);
    });
    return true;
  }

  if (message.action === 'CLEAR_LOGS') {
    chrome.storage.local.set({ syncLogs: [] }).then(() => {
      sendResponse({ success: true });
    });
    return true;
  }

  if (message.action === 'SAVE_BLOCKLIST') {
    getConfig().then((config) => {
      const newConfig = { ...config, distractionDomains: message.domains };
      saveConfig(newConfig).then(() => {
        sendResponse({ success: true });
      });
    });
    return true;
  }

  if (message.action === 'GET_BLOCKLIST') {
    getConfig().then((config) => {
      sendResponse({ success: true, domains: config.distractionDomains || DEFAULT_CONFIG.distractionDomains });
    });
    return true;
  }

  if (message.action === 'GET_DISTRACTION_STATS') {
    Promise.all([
      chrome.storage.local.get('distractionCount'),
      chrome.storage.local.get('distractionLogs')
    ]).then(([countResult, logsResult]) => {
      sendResponse({
        count: countResult.distractionCount || 0,
        logs: logsResult.distractionLogs || []
      });
    });
    return true;
  }

  if (message.action === 'BYPASS_DISTRACTION') {
    const { url, domain, tabId } = message;
    addBypass(tabId, domain).then(() => {
      chrome.tabs.update(tabId, { url }).then(() => {
        sendResponse({ success: true });
      });
    });
    return true;
  }

  if (message.action === 'COMPLETE_SUBTASK') {
    const { subtaskId } = message;
    completeSubtask(subtaskId).then((result) => {
      sendResponse(result);
    });
    return true;
  }
});

// Core logic functions
async function getConfig(): Promise<ExtensionConfig> {
  const result = await chrome.storage.local.get('config');
  return result.config || DEFAULT_CONFIG;
}

async function saveConfig(config: ExtensionConfig): Promise<boolean> {
  await chrome.storage.local.set({ config });
  return true;
}

async function getStatus(): Promise<AppStatus> {
  const result = await chrome.storage.local.get(['isConnected', 'activeTaskId', 'activeTaskTitle', 'activeTaskDescription', 'pendingSubtasks', 'isFocusSessionActive', 'lastSyncTime']);
  return {
    isConnected: result.isConnected || false,
    activeTaskId: result.activeTaskId || null,
    activeTaskTitle: result.activeTaskTitle || null,
    activeTaskDescription: result.activeTaskDescription || null,
    pendingSubtasks: result.pendingSubtasks || null,
    isFocusSessionActive: result.isFocusSessionActive || false,
    lastSyncTime: result.lastSyncTime || null,
  };
}

async function queueEvent(event: Omit<QueuedEvent, 'id' | 'timestamp'>): Promise<boolean> {
  const fullEvent: QueuedEvent = {
    ...event,
    id: crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2, 9),
    timestamp: new Date().toISOString(),
  };

  const data = await chrome.storage.local.get('eventQueue');
  const queue: QueuedEvent[] = data.eventQueue || [];

  // Enforce safety queue limit to prevent local storage quota overflow
  const MAX_QUEUE_SIZE = 1000;
  while (queue.length >= MAX_QUEUE_SIZE) {
    queue.shift();
  }

  queue.push(fullEvent);
  await chrome.storage.local.set({ eventQueue: queue });
  console.log('Queued event:', fullEvent);
  return true;
}

async function checkTabContext(tabId: number) {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (!tab.url) return;

    // Skip scanning browser system pages
    if (tab.url.startsWith('chrome://') || tab.url.startsWith('edge://') || tab.url.startsWith('about:') || tab.url.startsWith('chrome-extension://')) {
      return;
    }

    const url = new URL(tab.url);
    const domain = url.hostname;
    
    // Check if it's a distraction website during an active focus session
    const status = await getStatus();
    const config = await getConfig();
    const distractionDomains = config.distractionDomains || DEFAULT_CONFIG.distractionDomains || [];

    if (status.isFocusSessionActive) {
      const isDistracted = distractionDomains.some(d => domain.includes(d));

      if (isDistracted) {
        const bypassed = await isBypassed(tabId, domain);
        if (!bypassed) {
          console.log('Distraction detected:', domain, 'Redirecting to interstitial.');
          
          // Track local count of distraction triggers
          const stats = await chrome.storage.local.get('distractionCount');
          const count = (stats.distractionCount || 0) + 1;
          await chrome.storage.local.set({ distractionCount: count });

          // Maintain log of blocked sites
          const logData = await chrome.storage.local.get('distractionLogs');
          const logs: string[] = logData.distractionLogs || [];
          logs.push(`${new Date().toLocaleTimeString()} - Blocked ${domain}`);
          if (logs.length > 5) logs.shift();
          await chrome.storage.local.set({ distractionLogs: logs });

          await queueEvent({
            type: 'distraction',
            data: {
              domain,
              url: tab.url,
              title: tab.title || '',
              activeTask: status.activeTaskId
            }
          });

          // Redirect to interstitial page
          const interstitialUrl = chrome.runtime.getURL('interstitial.html') + 
            `?originalUrl=${encodeURIComponent(tab.url)}&domain=${encodeURIComponent(domain)}`;
          chrome.tabs.update(tabId, { url: interstitialUrl });
          return;
        }
      }
    }

    // Trigger normal active context snapshot
    await queueEvent({
      type: 'entity',
      data: {
        category: 'active_tab',
        value: tab.url,
        title: tab.title || ''
      }
    });

  } catch (err) {
    console.error('Error checking tab context:', err);
  }
}

async function syncViaCloudRelay(config: ExtensionConfig, queue: QueuedEvent[]): Promise<{ success: boolean; message: string }> {
  if (!config.cloudRelayPairingKey) {
    throw new Error('Cloud relay pairing key is not configured.');
  }

  const channelId = await deriveChannelId(config.cloudRelayPairingKey);
  const relayUrl = `${config.cloudRelayUrl}/${channelId}`;

  console.log(`Syncing via Zero-Knowledge Cloud Relay at ${relayUrl}...`);

  if (queue.length === 0) {
    await logSyncResult('Cloud relay validated. Queue empty.');
    return { success: true, message: 'Connected to relay. Event queue empty.' };
  }

  // Encrypt event queue JSON using AES-GCM
  const payloadStr = JSON.stringify({ events: queue });
  const encryptedBase64 = await encryptPayload(payloadStr, config.cloudRelayPairingKey);

  const response = await fetch(relayUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify({ payload: encryptedBase64 })
  });

  if (!response.ok) {
    throw new Error(`Relay server returned code ${response.status}`);
  }

  // Clear eventQueue on successful upload
  await chrome.storage.local.set({
    isConnected: true,
    lastSyncTime: new Date().toISOString(),
    eventQueue: []
  });

  console.log(`Successfully synced ${queue.length} events via Cloud Relay.`);
  return { success: true, message: `Synced ${queue.length} events via Cloud Relay.` };
}

async function syncEventsWithAndroid(): Promise<{ success: boolean; message: string }> {
  const config = await getConfig();
  const data = await chrome.storage.local.get('eventQueue');
  const queue: QueuedEvent[] = data.eventQueue || [];

  // 1. If Cloud Relay is explicitly enabled, route sync there immediately
  if (config.cloudRelayEnabled) {
    try {
      return await syncViaCloudRelay(config, queue);
    } catch (relayErr) {
      console.warn('Forced Cloud Relay failed:', relayErr);
      await chrome.storage.local.set({ isConnected: false });
      return { success: false, message: `Cloud relay error: ${(relayErr as Error).message}` };
    }
  }

  const url = `http://${config.androidIp}:${config.androidPort}/sync`;
  const statusUrl = `http://${config.androidIp}:${config.androidPort}/status`;

  console.log(`Syncing with Android Core at ${url}...`);

  try {
    // 2. Fetch current status of Android app locally
    const statusResponse = await fetch(statusUrl, {
      method: 'GET',
      headers: { 'Accept': 'application/json' }
    });

    if (!statusResponse.ok) {
      throw new Error(`Server returned status ${statusResponse.status}`);
    }

    const appState = await statusResponse.json();
    
    // Check if focus session status changed from active to inactive
    const currentStatus = await getStatus();
    if (currentStatus.isFocusSessionActive && !appState.isFocusSessionActive) {
      console.log('Focus session ended. Clearing bypass cache.');
      await clearBypasses();
    }

    // Cache the status details locally
    await chrome.storage.local.set({
      isConnected: true,
      activeTaskId: appState.activeTaskId || null,
      activeTaskTitle: appState.activeTaskTitle || null,
      activeTaskDescription: appState.activeTaskDescription || null,
      pendingSubtasks: appState.pendingSubtasks || null,
      isFocusSessionActive: appState.isFocusSessionActive || false,
      lastSyncTime: new Date().toISOString(),
    });

    if (queue.length > 0) {
      const syncResponse = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ events: queue })
      });

      if (syncResponse.ok) {
        // Sync completed, clear processed events from queue
        await chrome.storage.local.set({ eventQueue: [] });
        console.log(`Successfully synced ${queue.length} events.`);
        await logSyncResult(`Synced ${queue.length} events locally.`);
        return { success: true, message: `Synced ${queue.length} events.` };
      } else {
        throw new Error(`Sync post failed with code ${syncResponse.status}`);
      }
    }

    await logSyncResult('Connection validated. Queue empty.');
    return { success: true, message: 'Connected. Queue empty.' };

  } catch (err) {
    console.warn('Local sync failed. Checking Cloud Relay fallback... Error:', err);
    await logSyncResult(`Local connection failed. Trying Cloud Relay...`, true);
    
    // Fallback to Cloud Relay sync if pairing key is available
    if (config.cloudRelayPairingKey) {
      try {
        const relayResult = await syncViaCloudRelay(config, queue);
        await logSyncResult(`Relay Sync Success: ${relayResult.message}`);
        return relayResult;
      } catch (relayErr) {
        console.error('Cloud Relay fallback also failed:', relayErr);
        await logSyncResult(`Relay Sync Fail: ${(relayErr as Error).message}`, true);
      }
    }

    await chrome.storage.local.set({ isConnected: false });
    return { success: false, message: `Connection failed: ${(err as Error).message}` };
  }
}

async function logSyncResult(message: string, isError = false) {
  const data = await chrome.storage.local.get('syncLogs');
  const logs: Array<{ timestamp: string; message: string; isError: boolean }> = data.syncLogs || [];
  
  logs.push({
    timestamp: new Date().toLocaleTimeString(),
    message,
    isError
  });
  
  if (logs.length > 6) {
    logs.shift();
  }
  
  await chrome.storage.local.set({ syncLogs: logs });
}
