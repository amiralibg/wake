// The page's visible text, for Moments' change detection.
// params: { maxText }
return document.body ? document.body.innerText.slice(0, params.maxText) : '';
