// popup.ts for AKRAMYG Chrome Extension

document.addEventListener('DOMContentLoaded', () => {
  const statusDot = document.getElementById('status-dot') as HTMLElement;
  const statusText = document.getElementById('status-text') as HTMLElement;
  const activeTaskTitle = document.getElementById('active-task-title') as HTMLElement;
  const focusBadge = document.getElementById('focus-badge') as HTMLElement;
  const summaryArea = document.getElementById('summary-area') as HTMLElement;

  const btnAttach = document.getElementById('btn-attach') as HTMLButtonElement;
  const btnCapture = document.getElementById('btn-capture') as HTMLButtonElement;
  const btnSummarize = document.getElementById('btn-summarize') as HTMLButtonElement;
  const btnSaveSettings = document.getElementById('btn-save-settings') as HTMLButtonElement;
  const btnSaveRelaySettings = document.getElementById('btn-save-relay-settings') as HTMLButtonElement;

  const inputIp = document.getElementById('ip-address') as HTMLInputElement;
  const inputPort = document.getElementById('port') as HTMLInputElement;
  const inputCloudRelayEnabled = document.getElementById('cloud-relay-enabled') as HTMLInputElement;
  const inputRelayUrl = document.getElementById('relay-url') as HTMLInputElement;
  const inputRelayPairingKey = document.getElementById('relay-pairing-key') as HTMLInputElement;

  const btnScan = document.getElementById('btn-scan') as HTMLButtonElement;
  const btnSyncDetected = document.getElementById('btn-sync-detected') as HTMLButtonElement;
  const btnAddManual = document.getElementById('btn-add-manual') as HTMLButtonElement;
  const detectedItemsContainer = document.getElementById('detected-items-container') as HTMLElement;
  const detectedList = document.getElementById('detected-list') as HTMLElement;
  const manualFallbackContainer = document.getElementById('manual-fallback-container') as HTMLElement;
  const fallbackMessage = document.getElementById('fallback-message') as HTMLElement;
  const manualTaskTitle = document.getElementById('manual-task-title') as HTMLInputElement;
  const manualTaskDate = document.getElementById('manual-task-date') as HTMLInputElement;

  // Tab Navigation
  const tabBtnCapture = document.getElementById('tab-btn-capture') as HTMLElement;
  const tabBtnFocus = document.getElementById('tab-btn-focus') as HTMLElement;
  const tabBtnSync = document.getElementById('tab-btn-sync') as HTMLElement;
  const tabContentCapture = document.getElementById('tab-content-capture') as HTMLElement;
  const tabContentFocus = document.getElementById('tab-content-focus') as HTMLElement;
  const tabContentSync = document.getElementById('tab-content-sync') as HTMLElement;

  // Focus Tab Elements
  const distractionCountBadge = document.getElementById('distraction-count-badge') as HTMLElement;
  const distractionLogsFeed = document.getElementById('distraction-logs-feed') as HTMLElement;
  const blocklistDomains = document.getElementById('blocklist-domains') as HTMLTextAreaElement;
  const btnSaveBlocklist = document.getElementById('btn-save-blocklist') as HTMLButtonElement;

  // Sync Tab Elements
  const syncConsoleLog = document.getElementById('sync-console-log') as HTMLElement;
  const btnSyncNow = document.getElementById('btn-sync-now') as HTMLButtonElement;
  const btnClearLogs = document.getElementById('btn-clear-logs') as HTMLButtonElement;

  let localDetectedDeadlines: Array<{ title: string; date: string; sourceUrl: string }> = [];

  // Load Status, config and auto-scan page on startup
  loadStatus();
  loadConfig();
  loadBlocklist();
  loadDistractionStats();
  loadSyncLogs();
  setTimeout(triggerPageScan, 500);

  // Save Settings Click Handler
  btnSaveSettings.addEventListener('click', async () => {
    const ip = inputIp.value.trim();
    const port = inputPort.value.trim();

    if (!ip || !port) {
      alert('Please fill in both IP and Port.');
      return;
    }

    statusText.textContent = 'Updating...';
    btnSaveSettings.disabled = true;

    const configResult = await chrome.storage.local.get('config');
    const existingConfig = configResult.config || {};

    chrome.runtime.sendMessage(
      {
        action: 'UPDATE_CONFIG',
        config: {
          ...existingConfig,
          androidIp: ip,
          androidPort: port,
          syncIntervalMins: 1
        }
      },
      (response) => {
        btnSaveSettings.disabled = false;
        if (chrome.runtime.lastError) {
          statusText.textContent = 'Error saving config';
          return;
        }
        if (response && response.success) {
          setTimeout(loadStatus, 1000); // Wait a second for sync trigger
        } else {
          statusText.textContent = 'Error saving config';
        }
      }
    );
  });

  // Save Relay Settings Click Handler
  btnSaveRelaySettings.addEventListener('click', async () => {
    const enabled = inputCloudRelayEnabled.checked;
    const url = inputRelayUrl.value.trim();
    const pairingKey = inputRelayPairingKey.value.trim();

    if (enabled && (!url || !pairingKey)) {
      alert('Please configure both Relay Server URL and Pairing passphrase.');
      return;
    }

    statusText.textContent = 'Updating...';
    btnSaveRelaySettings.disabled = true;

    // Fetch existing config to merge it
    const configResult = await chrome.storage.local.get('config');
    const existingConfig = configResult.config || {};

    chrome.runtime.sendMessage(
      {
        action: 'UPDATE_CONFIG',
        config: {
          ...existingConfig,
          cloudRelayEnabled: enabled,
          cloudRelayUrl: url,
          cloudRelayPairingKey: pairingKey
        }
      },
      (response) => {
        btnSaveRelaySettings.disabled = false;
        if (chrome.runtime.lastError) {
          statusText.textContent = 'Error saving config';
          return;
        }
        if (response && response.success) {
          statusText.textContent = 'Relay config saved';
          setTimeout(loadStatus, 1000);
        } else {
          statusText.textContent = 'Error saving config';
        }
      }
    );
  });

  // Attach Page Click Handler
  btnAttach.addEventListener('click', async () => {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs.length === 0 || !tabs[0].url) {
      alert('No active page detected.');
      return;
    }

    const activeTab = tabs[0];
    btnAttach.disabled = true;
    btnAttach.textContent = 'Attaching...';

    chrome.runtime.sendMessage(
      {
        action: 'ADD_EVENT',
        event: {
          type: 'page_attach',
          data: {
            url: activeTab.url,
            title: activeTab.title || 'Untitled Page',
          }
        }
      },
      (response) => {
        btnAttach.disabled = false;
        btnAttach.textContent = 'Attach Page to Active Task';
        if (chrome.runtime.lastError) {
          alert('Failed to attach page.');
          return;
        }
        if (response && response.success) {
          alert('Page attachment queued and syncing!');
        } else {
          alert('Failed to attach page.');
        }
      }
    );
  });

  // Quick Capture Click Handler
  btnCapture.addEventListener('click', async () => {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs.length === 0 || !tabs[0].url) {
      alert('No active page detected.');
      return;
    }

    const activeTab = tabs[0];
    btnCapture.disabled = true;
    btnCapture.textContent = 'Sending...';

    // Queue a capture proposal
    chrome.runtime.sendMessage(
      {
        action: 'ADD_EVENT',
        event: {
          type: 'deadline', // Set as deadline type so Android Core creates a new proposed task
          data: {
            title: `Read: ${activeTab.title || 'Webpage'}`,
            date: new Date(Date.now() + 86400000 * 2).toISOString(), // Proposed deadline in 2 days
            sourceUrl: activeTab.url,
            isCaptureProposal: true
          }
        }
      },
      (response) => {
        btnCapture.disabled = false;
        btnCapture.textContent = 'Create Task from Page';
        if (chrome.runtime.lastError) {
          alert('Failed to send task proposal.');
          return;
        }
        if (response && response.success) {
          alert('Task proposal sent to AKRAMYG app!');
        } else {
          alert('Failed to send task proposal.');
        }
      }
    );
  });

  // Summarize Click Handler
  btnSummarize.addEventListener('click', async () => {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs.length === 0 || !tabs[0].id) {
      alert('No active page detected.');
      return;
    }

    const activeTab = tabs[0];
    btnSummarize.disabled = true;
    btnSummarize.textContent = 'Scraping content...';
    summaryArea.style.display = 'none';

    try {
      // Scrape webpage text via content script
      chrome.tabs.sendMessage(activeTab.id!, { action: 'SCRAPE_PAGE' }, async (scrapedData) => {
        if (!scrapedData || !scrapedData.text) {
          btnSummarize.disabled = false;
          btnSummarize.textContent = 'Summarize Current Page';
          alert('Could not read page text. Make sure you are on a webpage and refresh the page.');
          return;
        }

        btnSummarize.textContent = 'Generating summary...';

        // Retrieve config to execute direct fetch to Android Core
        const configResult = await chrome.storage.local.get('config');
        const config = configResult.config || { androidIp: '192.168.1.100', androidPort: '8080' };

        try {
          const response = await fetch(`http://${config.androidIp}:${config.androidPort}/summarize`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              url: scrapedData.url,
              title: scrapedData.title,
              text: scrapedData.text
            })
          });

          if (!response.ok) {
            throw new Error(`Server returned code ${response.status}`);
          }

          const resultData = await response.json();
          btnSummarize.disabled = false;
          btnSummarize.textContent = 'Summarize Current Page';
          
          summaryArea.style.display = 'block';
          summaryArea.textContent = resultData.summary || 'No summary returned by AKRAMYG Core.';

        } catch (fetchErr) {
          console.error(fetchErr);
          btnSummarize.disabled = false;
          btnSummarize.textContent = 'Summarize Current Page';
          alert('Failed to connect to Android app for summarization. Check server status.');
        }
      });
    } catch (msgErr) {
      console.error(msgErr);
      btnSummarize.disabled = false;
      btnSummarize.textContent = 'Summarize Current Page';
      alert('Unable to communicate with the page. Try refreshing the page.');
    }
  });

  // Page Scanner and manual fallback logic
  async function triggerPageScan() {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs.length === 0 || !tabs[0].id) {
      showManualFallback();
      return;
    }

    const activeTab = tabs[0];
    // Don't try scanning browser system pages
    if (activeTab.url && (activeTab.url.startsWith('chrome://') || activeTab.url.startsWith('edge://') || activeTab.url.startsWith('about:'))) {
      showManualFallback();
      return;
    }

    detectedList.innerHTML = '<div style="font-size:11px;color:var(--text-muted);">Scanning page...</div>';
    detectedItemsContainer.style.display = 'block';

    try {
      chrome.tabs.sendMessage(activeTab.id!, { action: 'MANUAL_SCAN_PAGE' }, (response: any) => {
        if (chrome.runtime.lastError || !response || !response.deadlines) {
          showManualFallback();
          return;
        }

        localDetectedDeadlines = response.deadlines as Array<{ title: string; date: string; sourceUrl: string }>;
        if (localDetectedDeadlines.length === 0) {
          showManualFallback();
        } else {
          renderDetectedItems(localDetectedDeadlines);
        }
      });
    } catch (e) {
      showManualFallback();
    }
  }

  function showManualFallback() {
    detectedItemsContainer.style.display = 'none';
    fallbackMessage.textContent = 'No deadlines auto-detected. Add manually:';
    manualFallbackContainer.style.display = 'block';
  }

  function renderDetectedItems(deadlines: typeof localDetectedDeadlines) {
    detectedList.innerHTML = '';
    detectedItemsContainer.style.display = 'block';
    manualFallbackContainer.style.display = 'none';
    
    deadlines.forEach((item, index) => {
      const div = document.createElement('div');
      div.className = 'detected-item';
      
      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.checked = true;
      checkbox.id = `detect-item-${index}`;
      
      const details = document.createElement('div');
      details.className = 'detected-item-details';
      
      const titleSpan = document.createElement('span');
      titleSpan.className = 'detected-item-title';
      titleSpan.textContent = item.title.length > 50 ? item.title.substring(0, 50) + '...' : item.title;
      
      const dateSpan = document.createElement('span');
      dateSpan.className = 'detected-item-date';
      dateSpan.textContent = `Due: ${item.date}`;
      
      details.appendChild(titleSpan);
      details.appendChild(dateSpan);
      
      div.appendChild(checkbox);
      div.appendChild(details);
      
      detectedList.appendChild(div);
    });
  }

  // Scan Button Click Handler
  btnScan.addEventListener('click', (e) => {
    e.preventDefault();
    triggerPageScan();
  });

  // Sync Detected Items Click Handler
  btnSyncDetected.addEventListener('click', () => {
    let syncCount = 0;
    localDetectedDeadlines.forEach((item, index) => {
      const checkbox = document.getElementById(`detect-item-${index}`) as HTMLInputElement;
      if (checkbox && checkbox.checked) {
        syncCount++;
        chrome.runtime.sendMessage({
          action: 'ADD_EVENT',
          event: {
            type: 'deadline',
            data: item
          }
        });
      }
    });

    if (syncCount > 0) {
      alert(`Queued ${syncCount} deadlines for sync!`);
      triggerPageScan(); // Refresh scan list
    } else {
      alert('No items selected.');
    }
  });

  // Manual Add Task Click Handler
  btnAddManual.addEventListener('click', async () => {
    const title = manualTaskTitle.value.trim();
    const dateStr = manualTaskDate.value.trim();

    if (!title) {
      alert('Please enter a task title.');
      return;
    }

    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    const sourceUrl = tabs.length > 0 ? tabs[0].url || '' : '';

    btnAddManual.disabled = true;
    btnAddManual.textContent = 'Adding...';

    // Date is optional, default to +2 days if not set
    const finalDate = dateStr ? new Date(dateStr).toISOString() : new Date(Date.now() + 86400000 * 2).toISOString();

    chrome.runtime.sendMessage(
      {
        action: 'ADD_EVENT',
        event: {
          type: 'deadline',
          data: {
            title: title,
            date: finalDate,
            sourceUrl: sourceUrl,
            isCaptureProposal: true
          }
        }
      },
      (response) => {
        btnAddManual.disabled = false;
        btnAddManual.textContent = 'Add Task';
        if (chrome.runtime.lastError) {
          alert('Failed to send task.');
          return;
        }
        if (response && response.success) {
          alert('Manual task added successfully!');
          manualTaskTitle.value = '';
          manualTaskDate.value = '';
        } else {
          alert('Failed to add manual task.');
        }
      }
    );
  });

  // Load configuration from chrome storage
  async function loadConfig() {
    const result = await chrome.storage.local.get('config');
    if (result.config) {
      inputIp.value = result.config.androidIp || '';
      inputPort.value = result.config.androidPort || '8080';
      inputCloudRelayEnabled.checked = result.config.cloudRelayEnabled || false;
      inputRelayUrl.value = result.config.cloudRelayUrl || '';
      inputRelayPairingKey.value = result.config.cloudRelayPairingKey || '';
    }
  }

  // Load status values and update UI
  async function loadStatus() {
    chrome.runtime.sendMessage({ action: 'GET_STATUS' }, (status) => {
      if (chrome.runtime.lastError) {
        statusDot.className = 'status-dot status-disconnected';
        statusText.textContent = 'Disconnected';
        return;
      }
      if (status) {
        // Connection Dot
        if (status.isConnected) {
          statusDot.className = 'status-dot status-connected';
          statusText.textContent = 'Connected';
        } else {
          statusDot.className = 'status-dot status-disconnected';
          statusText.textContent = 'Disconnected';
        }

        // Active Task
        if (status.activeTaskTitle) {
          activeTaskTitle.textContent = status.activeTaskTitle;
        } else {
          activeTaskTitle.textContent = 'None';
        }

        // Focus Session
        if (status.isFocusSessionActive) {
          focusBadge.style.display = 'inline-block';
        } else {
          focusBadge.style.display = 'none';
        }
      }
    });
  }

  // Tab Navigation Handlers
  function switchToTab(tabName: 'capture' | 'focus' | 'sync') {
    // Remove active class from all buttons
    tabBtnCapture.classList.remove('active');
    tabBtnFocus.classList.remove('active');
    tabBtnSync.classList.remove('active');
    // Hide all contents
    tabContentCapture.style.display = 'none';
    tabContentFocus.style.display = 'none';
    tabContentSync.style.display = 'none';

    if (tabName === 'capture') {
      tabBtnCapture.classList.add('active');
      tabContentCapture.style.display = 'block';
    } else if (tabName === 'focus') {
      tabBtnFocus.classList.add('active');
      tabContentFocus.style.display = 'block';
      loadDistractionStats();
    } else {
      tabBtnSync.classList.add('active');
      tabContentSync.style.display = 'block';
      loadSyncLogs();
    }
  }

  tabBtnCapture.addEventListener('click', () => switchToTab('capture'));
  tabBtnFocus.addEventListener('click', () => switchToTab('focus'));
  tabBtnSync.addEventListener('click', () => switchToTab('sync'));

  // Load blocklist from storage
  async function loadBlocklist() {
    chrome.runtime.sendMessage({ action: 'GET_BLOCKLIST' }, (response) => {
      if (response && response.domains) {
        blocklistDomains.value = response.domains.join(', ');
      }
    });
  }

  // Save blocklist handler
  btnSaveBlocklist.addEventListener('click', async () => {
    const domainList = blocklistDomains.value.split(',').map(d => d.trim()).filter(d => d.length > 0);
    chrome.runtime.sendMessage({ action: 'SAVE_BLOCKLIST', domains: domainList }, (response) => {
      if (response && response.success) {
        alert('Blocklist saved successfully!');
      } else {
        alert('Failed to save blocklist.');
      }
    });
  });

  // Load distraction stats
  async function loadDistractionStats() {
    chrome.runtime.sendMessage({ action: 'GET_DISTRACTION_STATS' }, (response: any) => {
      if (response) {
        distractionCountBadge.textContent = `${response.count} times`;
        if (response.logs && response.logs.length > 0) {
          distractionLogsFeed.innerHTML = (response.logs as string[]).map((log: string) => `<div style="padding:2px 0;font-size:10px;">${log}</div>`).join('');
        } else {
          distractionLogsFeed.innerHTML = 'No distractions blocked yet in this session.';
        }
      }
    });
  }

  // Load sync logs
  async function loadSyncLogs() {
    const result = await chrome.storage.local.get('syncLogs');
    const logs = (result.syncLogs as Array<{ timestamp: string; message: string; isError: boolean }>) || [];
    if (logs.length > 0) {
      syncConsoleLog.innerHTML = logs.map((log: { timestamp: string; message: string; isError: boolean }) => {
        const colorClass = log.isError ? 'console-log-error' : '';
        return `<div class="console-log-line ${colorClass}">${log.timestamp} - ${log.message}</div>`;
      }).join('');
    } else {
      syncConsoleLog.textContent = 'No sync operations logged yet.';
    }
  }

  // Sync Now button handler
  btnSyncNow.addEventListener('click', async () => {
    btnSyncNow.disabled = true;
    btnSyncNow.textContent = 'Syncing...';
    chrome.runtime.sendMessage({ action: 'SYNC_NOW' }, async (response) => {
      btnSyncNow.disabled = false;
      btnSyncNow.textContent = 'Force Sync Now';
      if (response && response.success) {
        alert('Sync successful!');
        loadStatus();
        loadSyncLogs();
      } else {
        alert(`Sync failed: ${response ? response.message : 'Unknown error'}`);
        loadSyncLogs();
      }
    });
  });

  // Clear Logs button handler
  btnClearLogs.addEventListener('click', async () => {
    chrome.runtime.sendMessage({ action: 'CLEAR_LOGS' }, (response) => {
      if (response && response.success) {
        loadSyncLogs();
        alert('Logs cleared!');
      }
    });
  });

  // Periodically refresh status and logs
  setInterval(() => {
    loadStatus();
    if (tabContentSync.style.display !== 'none') {
      loadSyncLogs();
    }
    if (tabContentFocus.style.display !== 'none') {
      loadDistractionStats();
    }
  }, 2000);
});
