// Returns Wake's bridge to the host: `post(channel, message)`.
// WebKit (macOS, WebKitGTK) has a message handler per channel; WebView2 has one
// channel for everything, so the channel travels with the message.
const handlers = window.webkit && window.webkit.messageHandlers;
if (handlers) {
  return {
    post(channel, message) {
      try { handlers[channel].postMessage(message); } catch (e) {}
    },
  };
}
const view = window.chrome && window.chrome.webview;
return {
  post(channel, message) {
    try { view.postMessage({ channel, message }); } catch (e) {}
  },
};
