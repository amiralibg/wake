(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const tabs = await chrome.tabs.query({ currentWindow: true });
  const { seen = 0 } = await chrome.storage.local.get('seen');
  document.getElementById('title').textContent = tab ? `Active: ${tab.title}` : 'No active tab';
  document.getElementById('count').textContent = `${tabs.length} tab(s) in this window`;
  document.getElementById('seen').textContent = `Content script ran on ${seen} page(s)`;
  document.getElementById('options').onclick = () => chrome.runtime.openOptionsPage();
})();
