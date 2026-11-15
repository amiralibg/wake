// Badge = number of tabs in the current window, so tab reporting is visible at a glance.
async function updateBadge() {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  await chrome.action.setBadgeText({ text: String(tabs.length) });
}
chrome.tabs.onCreated.addListener(updateBadge);
chrome.tabs.onRemoved.addListener(updateBadge);
chrome.tabs.onActivated.addListener(updateBadge);
chrome.runtime.onInstalled.addListener(updateBadge);
chrome.runtime.onStartup.addListener(updateBadge);
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message.type === 'seen') {
    chrome.storage.local.get({ seen: 0 }).then(({ seen }) => {
      chrome.storage.local.set({ seen: seen + 1 });
      reply({ seen: seen + 1 });
    });
    return true;
  }
});
updateBadge();

// Right-click menu and keyboard commands.
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'wake-test-page', title: 'Wake Test: count this page', contexts: ['page'] });
  chrome.contextMenus.create({ id: 'wake-test-link', title: 'Wake Test: note this link', contexts: ['link'] });
});
chrome.contextMenus.onClicked.addListener(async (info) => {
  const { menuClicks = 0 } = await chrome.storage.local.get('menuClicks');
  await chrome.storage.local.set({ menuClicks: menuClicks + 1 });
  await chrome.action.setBadgeText({ text: 'M' + (menuClicks + 1) });
});
chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'count-columns') {
    const tabs = await chrome.tabs.query({ currentWindow: true });
    await chrome.action.setBadgeText({ text: 'K' + tabs.length });
  }
});
