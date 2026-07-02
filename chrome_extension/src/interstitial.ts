// interstitial.ts for AKRAMYG Chrome Extension

document.addEventListener('DOMContentLoaded', () => {
  const params = new URLSearchParams(window.location.search);
  const originalUrl = params.get('originalUrl') || 'https://google.com';
  const domain = params.get('domain') || '';

  const taskTitleEl = document.getElementById('task-title')!;
  const taskDescEl = document.getElementById('task-desc')!;
  const nudgeContainer = document.getElementById('nudge-container')!;
  const nudgeStepEl = document.getElementById('nudge-step')!;
  const btnDone = (document.getElementById('btn-done') as HTMLButtonElement)!;
  const btnFocus = (document.getElementById('btn-focus') as HTMLButtonElement)!;
  const linkBypass = document.getElementById('link-bypass')!;

  function refreshStatus() {
    chrome.runtime.sendMessage({ action: 'GET_STATUS' }, (status) => {
      if (chrome.runtime.lastError) {
        taskTitleEl.textContent = 'Disconnected';
        taskDescEl.textContent = 'Unable to check status from extension background.';
        return;
      }

      if (status && status.isFocusSessionActive) {
        taskTitleEl.textContent = status.activeTaskTitle || 'Unnamed Task';
        taskDescEl.textContent = status.activeTaskDescription || 'No details provided.';
        
        const subtasks = status.pendingSubtasks || [];
        if (subtasks.length > 0) {
          const nextStep = subtasks[0];
          nudgeStepEl.textContent = nextStep.title;
          nudgeContainer.style.display = 'block';
          btnDone.style.display = 'block';
          
          btnDone.onclick = () => {
            btnDone.disabled = true;
            btnDone.textContent = 'Updating...';
            chrome.runtime.sendMessage({ action: 'COMPLETE_SUBTASK', subtaskId: nextStep.id }, (response) => {
              btnDone.disabled = false;
              btnDone.textContent = '✅ Completed: Mark Step as Done';
              if (response && response.success) {
                // Reload status to show the next pending subtask
                refreshStatus();
              } else {
                alert('Could not complete subtask. Make sure the companion app is connected.');
              }
            });
          };
        } else {
          nudgeStepEl.textContent = 'You have completed all execution steps! Take a moment to breathe or add a next step.';
          nudgeContainer.style.display = 'block';
          btnDone.style.display = 'none';
        }
      } else {
        taskTitleEl.textContent = 'No Focus Session Active';
        taskDescEl.textContent = 'No active task on your phone companion. Close this tab and get to work!';
        nudgeContainer.style.display = 'none';
        btnDone.style.display = 'none';
      }
    });
  }

  // Initial load
  refreshStatus();

  // Focus Button handler: close the tab to focus
  btnFocus.addEventListener('click', () => {
    chrome.tabs.getCurrent((tab) => {
      if (tab?.id) {
        chrome.tabs.remove(tab.id);
      } else {
        window.close();
      }
    });
  });

  // Bypass link handler: notify background of bypass and update tab url
  linkBypass.addEventListener('click', (e) => {
    e.preventDefault();
    chrome.tabs.getCurrent((tab) => {
      const tabId = tab?.id;
      if (tabId) {
        chrome.runtime.sendMessage({
          action: 'BYPASS_DISTRACTION',
          url: originalUrl,
          domain: domain,
          tabId: tabId
        }, (response) => {
          if (chrome.runtime.lastError || !response || !response.success) {
            // Fallback navigation in case of error
            window.location.href = originalUrl;
          }
        });
      } else {
        window.location.href = originalUrl;
      }
    });
  });
});
