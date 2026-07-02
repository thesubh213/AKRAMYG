// content.ts for AKRAMYG Chrome Extension

// Listen for messages from the popup or background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'SCRAPE_PAGE') {
    const pageText = getCleanBodyText();
    const title = document.title;
    const url = window.location.href;
    sendResponse({ text: pageText, title, url });
  }

  if (message.action === 'HIGHLIGHT_TEXT') {
    const selection = window.getSelection();
    if (selection) {
      sendResponse({ text: selection.toString() });
    } else {
      sendResponse({ text: '' });
    }
  }

  if (message.action === 'MANUAL_SCAN_PAGE') {
    const deadlines = performDeadlineScan();
    const entities = performEntityScan();
    sendResponse({ deadlines, entities });
  }
});

// Automatically scan the page on load to detect deadlines and entities
function autoScanPage() {
  // Wait a moment for dynamic page rendering
  setTimeout(() => {
    scanPageForDeadlines();
    scanPageForEntities();
  }, 1500);
}

window.addEventListener('load', autoScanPage);
document.addEventListener('DOMContentLoaded', autoScanPage);

// Extract cleaned visible text from page
function getCleanBodyText(): string {
  if (!document.body) return '';
  // Remove script, style, and navigation elements
  const bodyClone = document.body.cloneNode(true) as HTMLElement;
  const elementsToRemove = bodyClone.querySelectorAll('script, style, nav, footer, header, iframe');
  elementsToRemove.forEach(el => el.remove());
  
  // Get clean text with spaces
  let text = bodyClone.innerText || bodyClone.textContent || '';
  // Collapse whitespace
  text = text.replace(/\s+/g, ' ').trim();
  // Return first 50,000 characters to prevent huge payloads
  return text.substring(0, 50000);
}

// Scrape page for candidate deadlines (returns array of items)
function performDeadlineScan(): Array<{ title: string; date: string; sourceUrl: string }> {
  if (!document.body) return [];
  const url = window.location.href;
  const pageText = document.body.innerText || '';
  const detectedDeadlines: Array<{ title: string; date: string; sourceUrl: string }> = [];

  // 1. LMS Canvas specific detection
  if (url.includes('canvas') || url.includes('instructure.com')) {
    const assignmentRows = document.querySelectorAll(
      '.student-assignment-row, .assignment, .ig-row, .assignment-list-item, li.assignment'
    );
    assignmentRows.forEach(row => {
      const titleEl = row.querySelector('.title, .assignment_title, .ig-title, a.ig-title, .assignment-title');
      const dueEl = row.querySelector('.due_date, .display_due_date, .due, .due-date, span.due-date');
      if (titleEl && dueEl && titleEl.textContent && dueEl.textContent) {
        detectedDeadlines.push({
          title: `[Canvas] ${titleEl.textContent.trim()}`,
          date: dueEl.textContent.trim(),
          sourceUrl: url
        });
      }
    });
  }

  // 2. GitHub specific detection (Milestones or Issue lists)
  if (url.includes('github.com')) {
    const milestoneItems = document.querySelectorAll('.milestone-card, .milestone, .milestone-card-header, li.milestone');
    milestoneItems.forEach(item => {
      const titleEl = item.querySelector('.milestone-title-link, .milestone-title a, h2.milestone-title a, a');
      const dueEl = item.querySelector('.milestone-meta-item, .milestone-meta, .due-date, span.due-date, span');
      if (titleEl && dueEl && titleEl.textContent && dueEl.textContent && dueEl.textContent.includes('Due')) {
        detectedDeadlines.push({
          title: `[GitHub Milestone] ${titleEl.textContent.trim()}`,
          date: dueEl.textContent.trim().replace('Due by', '').trim(),
          sourceUrl: url
        });
      }
    });
  }

  // 3. Generic Regex Deadline Scraping
  const regexPatterns = [
    /(?:due\s+by|due|deadline)\s*[:\-]?\s*([A-Za-z]+\s+\d{1,2}(?:\s*,\s*\d{4})?|\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})/gi
  ];

  regexPatterns.forEach(pattern => {
    let match;
    const textSnippet = pageText.substring(0, 10000); // Check first 10k chars
    while ((match = pattern.exec(textSnippet)) !== null) {
      const extractedDate = match[1];
      const index = match.index;
      const contextText = textSnippet.substring(Math.max(0, index - 50), index).trim();
      let cleanContext = contextText.replace(/\r?\n|\r/g, ' ').replace(/\s+/g, ' ').trim();
      
      cleanContext = cleanContext.replace(/^[^a-zA-Z0-9]+/, '');
      
      if (cleanContext.length > 50) {
        cleanContext = '...' + cleanContext.substring(cleanContext.length - 47);
      }
      
      if (cleanContext.length < 3) {
        cleanContext = document.title || 'Page Deadline';
      }
      
      detectedDeadlines.push({
        title: `Deadline: "${cleanContext}"`,
        date: extractedDate.trim(),
        sourceUrl: url
      });
    }
  });

  return Array.from(new Set(detectedDeadlines.map(d => JSON.stringify(d)))).map(s => JSON.parse(s));
}

function scanPageForDeadlines() {
  const uniqueDeadlines = performDeadlineScan();
  if (uniqueDeadlines.length > 0) {
    console.log('AKRAMYG Sensor: Detected deadlines:', uniqueDeadlines);
    uniqueDeadlines.forEach(deadline => {
      chrome.runtime.sendMessage({
        action: 'ADD_EVENT',
        event: {
          type: 'deadline',
          data: deadline
        }
      });
    });
  }
}

// Scrape page for other useful entities (returns array of items)
function performEntityScan(): Array<{ category: string; value: string; title: string }> {
  if (!document.body) return [];
  const url = window.location.href;
  const pageText = document.body.innerText || '';
  const detectedEntities: Array<{ category: string; value: string; title: string }> = [];

  // Find GitHub repository URLs on page
  const githubRepoRegex = /https:\/\/github\.com\/([A-Za-z0-9_\-\.]+)\/([A-Za-z0-9_\-\.]+)/gi;
  let match;
  while ((match = githubRepoRegex.exec(pageText)) !== null) {
    detectedEntities.push({
      category: 'repository',
      value: match[0],
      title: `${match[1]}/${match[2]}`
    });
  }

  // Find Google Meet / Zoom Links
  const meetingRegex = /(https:\/\/(?:meet\.google\.com|zoom\.us\/j)\/[A-Za-z0-9_\-\?&=]+)/gi;
  while ((match = meetingRegex.exec(pageText)) !== null) {
    detectedEntities.push({
      category: 'meeting_link',
      value: match[0],
      title: 'Meeting Link'
    });
  }

  return Array.from(new Set(detectedEntities.map(e => JSON.stringify(e)))).map(s => JSON.parse(s));
}

function scanPageForEntities() {
  const uniqueEntities = performEntityScan();
  uniqueEntities.forEach(entity => {
    chrome.runtime.sendMessage({
      action: 'ADD_EVENT',
      event: {
        type: 'entity',
        data: entity
      }
    });
  });
}
