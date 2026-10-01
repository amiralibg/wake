// "deleted", "blocked" (the page still has it open; the delete waits), or "error".
// params: { name }
return await new Promise((resolve) => {
  const r = indexedDB.deleteDatabase(params.name);
  r.onsuccess = () => resolve('deleted');
  r.onerror = () => resolve('error');
  r.onblocked = () => resolve('blocked');
});
