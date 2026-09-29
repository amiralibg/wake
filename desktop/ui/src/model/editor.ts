// Opens source files at a line in the editor chosen in Settings (port of
// EditorOpener.swift). Cursor, VS Code and Zed register URL schemes that take
// `path:line:column`; Xcode is macOS only and isn't offered here.

import { host } from '../host/host';
import { settings } from './settings';
import { projects, resolveSourceMap, projectRelativePath } from './developer';
import type { ComponentPick, SourceLocation } from './devtools-log';

const isAbsolute = (path: string) => path.startsWith('/') || /^[A-Za-z]:[\\/]/.test(path);

export function openFile(path: string, line: number, column: number) {
  const scheme = { cursor: 'cursor', vscode: 'vscode', zed: 'zed', xcode: 'vscode' }[settings.editor] ?? 'vscode';
  const normalized = path.replace(/\\/g, '/');
  const withSlash = normalized.startsWith('/') ? normalized : '/' + normalized;
  host.send('open.external', { url: `${scheme}://file${encodeURI(withSlash)}:${line}:${column}` });
}

async function openInProject(relativePath: string, line: number, column: number, pageURL: string | null): Promise<boolean> {
  let project = projects.project(pageURL)?.data ?? (pageURL ? projects.makeProject(pageURL) : null);
  if (project && !project.folderPath) project = await projects.chooseFolder(project);
  const folder = project?.folderPath;
  if (!folder) return false;
  const separator = folder.includes('\\') && !folder.includes('/') ? '\\' : '/';
  openFile(folder.replace(/[\\/]$/, '') + separator + relativePath, line, column);
  return true;
}

/** A component picked with the inspector: React gives absolute paths; Vue and Svelte relative ones. */
export async function openInEditor(pick: ComponentPick): Promise<boolean> {
  if (!pick.file) return false;
  if (isAbsolute(pick.file)) {
    openFile(pick.file, pick.line ?? 1, 1);
    return true;
  }
  return openInProject(pick.file, pick.line ?? 1, 1, pick.pageURL);
}

/** A console location, resolved through its source map to a file in the page's project. */
export async function openLocation(location: SourceLocation): Promise<boolean> {
  const original = await resolveSourceMap(location);
  if (!original) {
    // No source map: the served path is often the file itself (Vite).
    let path = location.url;
    try {
      path = new URL(location.url).pathname.replace(/^\/+/, '');
    } catch {}
    return openInProject(path, location.line, location.column, location.url);
  }
  if (isAbsolute(original.source)) {
    const exists = await host.call<boolean>('fs.exists', { path: original.source }).catch(() => false);
    if (exists) {
      openFile(original.source, original.line, original.column);
      return true;
    }
  }
  return openInProject(projectRelativePath(original.source), original.line, original.column, location.url);
}
