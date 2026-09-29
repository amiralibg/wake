import { observer } from 'mobx-react-lite';
import { useState } from 'react';
import { Folder, Plus } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { settings, type Editor } from '../../model/settings';
import { projects, ENVIRONMENTS, ENVIRONMENT_LABELS, type DevEnvironment, type DevProjectData } from '../../model/developer';
import { host } from '../../host/host';
import { Group, Row, Select, Switch } from './components';

const PLACEHOLDERS: Record<DevEnvironment, string> = {
  local: 'http://localhost:5173',
  staging: 'https://staging.example.com',
  production: 'https://example.com',
};

export const DeveloperSection = observer(function DeveloperSection(_: { browser: BrowserModel }) {
  const [editing, setEditing] = useState<DevProjectData | null>(null);
  return (
    <>
      <Group title="Developer mode">
        <Row label="On automatically for localhost" detail="Captures console, network and hot reload for local dev servers. Any thread can switch it on or off (Ctrl+Shift+E).">
          <Switch checked={settings.autoEnableForLocalhost} onChange={(v) => settings.set('developer.autoLocalhost', v)} />
        </Row>
        <Row label="Find local dev servers" detail="Checks ports 3000–3010, 4200, 5173–5180, 6006, 8000 and 8080 and lists them in the app capsule.">
          <Switch checked={settings.scansPorts} onChange={(v) => settings.set('developer.scanPorts', v)} />
        </Row>
        <Row label="Open in editor" detail="Where console errors and inspected components open.">
          <Select<Editor>
            value={settings.editor === 'xcode' ? 'vscode' : settings.editor}
            options={[
              { value: 'cursor', label: 'Cursor' },
              { value: 'vscode', label: 'VS Code' },
              { value: 'zed', label: 'Zed' },
            ]}
            onChange={(v) => settings.set('developer.editor', v)}
          />
        </Row>
        <Row
          label="Web Inspector"
          detail="The engine's full inspector (WebKit's Web Inspector on Linux, Edge DevTools on Windows) from DevTools and F12."
        >
          <Switch checked={settings.webInspectorEnabled} onChange={(v) => settings.set('developer.webInspector', v)} />
        </Row>
      </Group>
      <Group title="Projects">
        {projects.projects.length === 0 && (
          <div className="secondary settings-note">
            Add a project to switch between local, staging and production with the same path, see its git branch, and open errors in your editor.
          </div>
        )}
        {projects.projects.map((project) => (
          <div key={project.id} className="project-row">
            <Folder size={15} color={project.folderPath ? 'var(--accent)' : 'var(--text-2)'} />
            <div className="project-text">
              <div className="project-name">{project.name}</div>
              <div className="secondary small truncate">
                {ENVIRONMENTS.filter((e) => project.origins[e])
                  .map((e) => `${ENVIRONMENT_LABELS[e]}: ${project.origins[e]}`)
                  .join('  ·  ')}
              </div>
            </div>
            <button className="button" onClick={() => setEditing({ ...project, origins: { ...project.origins } })}>
              Edit…
            </button>
          </div>
        ))}
        <button className="add-row" onClick={() => setEditing({ id: crypto.randomUUID(), name: 'New Project', origins: {}, folderPath: null })}>
          <Plus size={14} /> Add Project
        </button>
      </Group>
      {editing && <ProjectEditor project={editing} onClose={() => setEditing(null)} />}
    </>
  );
});

function ProjectEditor({ project: initial, onClose }: { project: DevProjectData; onClose: () => void }) {
  const [project, setProject] = useState(initial);
  const exists = projects.projects.some((p) => p.id === project.id);
  const valid = project.name.trim() && Object.values(project.origins).some(Boolean);
  const setOrigin = (env: DevEnvironment, value: string) => {
    const origins = { ...project.origins };
    if (value.trim()) origins[env] = value.trim();
    else delete origins[env];
    setProject({ ...project, origins });
  };
  return (
    <div className="confirm-backdrop" onPointerDown={onClose}>
      <div className="confirm glass-strong project-editor" onPointerDown={(e) => e.stopPropagation()}>
        <div className="confirm-title">{exists ? 'Edit Project' : 'New Project'}</div>
        <label className="form-row">
          <span>Name</span>
          <input className="text-field" value={project.name} onChange={(e) => setProject({ ...project, name: e.target.value })} />
        </label>
        {ENVIRONMENTS.map((env) => (
          <label key={env} className="form-row">
            <span>{ENVIRONMENT_LABELS[env]}</span>
            <input className="text-field" placeholder={PLACEHOLDERS[env]} value={project.origins[env] ?? ''} onChange={(e) => setOrigin(env, e.target.value)} />
          </label>
        ))}
        <div className="form-row">
          <span>Folder</span>
          <span className={`truncate ${project.folderPath ? '' : 'secondary'}`} style={{ flex: 1, direction: 'rtl', textAlign: 'left' }}>
            {project.folderPath ?? 'Not linked'}
          </span>
          <button
            className="button"
            onClick={async () => {
              const folder = await host.call<string | null>('dialog.folder', { title: `Choose the folder for ${project.name}` });
              if (folder) setProject({ ...project, folderPath: folder });
            }}
          >
            {project.folderPath ? 'Change…' : 'Link…'}
          </button>
        </div>
        <div className="confirm-actions">
          {exists && (
            <button
              className="button danger"
              style={{ marginRight: 'auto' }}
              onClick={() => {
                projects.delete(project);
                onClose();
              }}
            >
              Delete Project
            </button>
          )}
          <button className="button" onClick={onClose}>
            Cancel
          </button>
          <button
            className="button primary"
            disabled={!valid}
            onClick={() => {
              projects.save(project);
              onClose();
            }}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
