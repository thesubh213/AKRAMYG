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
  const btnCompleteTask = (document.getElementById('btn-complete-task') as HTMLButtonElement)!;
  const btnFocus = (document.getElementById('btn-focus') as HTMLButtonElement)!;
  const linkBypass = document.getElementById('link-bypass')!;
  
  const distractionNotice = document.getElementById('distraction-notice')!;
  const quoteEl = document.getElementById('interstitial-quote')!;

  // Render distraction alert if domain is present
  if (domain) {
    distractionNotice.innerHTML = `⚠️ Blocked visit to <strong>${domain}</strong> during active focus!`;
    distractionNotice.style.display = 'block';
  }

  function refreshStatus() {
    chrome.runtime.sendMessage({ action: 'GET_STATUS' }, (status) => {
      if (chrome.runtime.lastError) {
        taskTitleEl.textContent = 'Disconnected';
        taskDescEl.textContent = 'Unable to check status from extension background.';
        return;
      }

      if (status && status.isFocusSessionActive) {
        const taskTitle = status.activeTaskTitle || 'Unnamed Task';
        taskTitleEl.textContent = taskTitle;
        taskDescEl.textContent = status.activeTaskDescription || 'No details provided.';
        
        // Personalize the quote nudge
        quoteEl.innerHTML = `“Hey! Instead of checking <strong>${domain || 'distractions'}</strong>, how about we spend just 5 minutes on <strong>${taskTitle}</strong>?”`;

        // Render whole task completion action
        btnCompleteTask.style.display = 'block';
        btnCompleteTask.onclick = () => {
          btnCompleteTask.disabled = true;
          btnCompleteTask.textContent = 'Completing Task...';
          chrome.runtime.sendMessage({ action: 'COMPLETE_TASK', taskId: status.activeTaskId }, (response) => {
            btnCompleteTask.disabled = false;
            btnCompleteTask.textContent = '🎉 Completed: Mark Whole Task as Done';
            if (response && response.success) {
              refreshStatus();
            } else {
              alert('Could not complete task. Ensure the companion app is running.');
            }
          });
        };

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
                refreshStatus();
              } else {
                alert('Could not complete subtask. Ensure the companion app is connected.');
              }
            });
          };
        } else {
          nudgeStepEl.textContent = 'All checklist steps are done! Take a moment to breathe or mark the task complete.';
          nudgeContainer.style.display = 'block';
          btnDone.style.display = 'none';
        }
      } else {
        taskTitleEl.textContent = 'No Focus Session Active';
        taskDescEl.textContent = 'No focus task is active on your phone. Close this tab and get to work!';
        quoteEl.innerHTML = `“Avoidance caught! Close this tab and keep pushing.”`;
        nudgeContainer.style.display = 'none';
        btnDone.style.display = 'none';
        btnCompleteTask.style.display = 'none';
      }
    });
  }

  // Initial load
  refreshStatus();

  // Focus Button handler: close the tab using background script
  btnFocus.addEventListener('click', () => {
    chrome.runtime.sendMessage({ action: 'CLOSE_CURRENT_TAB' });
  });

  // Bypass link handler: notify background of bypass and update tab url
  linkBypass.addEventListener('click', (e) => {
    e.preventDefault();
    chrome.runtime.sendMessage({
      action: 'BYPASS_DISTRACTION',
      url: originalUrl,
      domain: domain
    }, (response) => {
      if (chrome.runtime.lastError || !response || !response.success) {
        window.location.href = originalUrl;
      }
    });
  });
});
