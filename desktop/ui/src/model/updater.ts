// Auto-update (the Mac app's AppUpdater.swift uses Sparkle). The host checks the
// latest GitHub release, downloads this platform's package, verifies its Ed25519
// signature against the key built into the app, and installs it: the NSIS
// installer on Windows, the AppImage swapped in place on Linux. Other Linux
// packages (deb, Flatpak) update through their package manager.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { settings } from './settings';

interface UpdateInfo {
  version: string;
  /** False without a signing key, or when installed through a package manager. */
  canUpdate: boolean;
  reason: string;
}

interface Release {
  version: string;
  notes: string;
  url: string;
}

const DAY = 86_400_000;

class Updater {
  version = '';
  isAvailable = false;
  unavailableReason = 'Checking…';
  state: 'idle' | 'checking' | 'installing' = 'idle';
  available: Release | null = null;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  get lastChecked(): number | null {
    return settings.get<number | null>('updates.lastChecked', null);
  }

  get automaticallyChecks(): boolean {
    return settings.get('updates.automatic', true);
  }

  setAutomaticallyChecks(on: boolean) {
    settings.set('updates.automatic', on);
  }

  async start() {
    const info = await host.call<UpdateInfo>('update.info').catch(() => null);
    runInAction(() => {
      this.version = info?.version ?? '';
      this.isAvailable = !!info?.canUpdate;
      this.unavailableReason = info?.reason ?? 'Updates are off in this build.';
    });
    if (this.isAvailable && this.automaticallyChecks && Date.now() - (this.lastChecked ?? 0) > DAY) {
      await this.check(false);
    }
  }

  async check(userInitiated: boolean) {
    if (!this.isAvailable || this.state !== 'idle') return;
    this.state = 'checking';
    this.error = null;
    try {
      const release = await host.call<Release | null>('update.check');
      runInAction(() => (this.available = release));
      settings.set('updates.lastChecked', Date.now());
    } catch (error) {
      runInAction(() => (this.error = String(error)));
      if (userInitiated) throw error;
    } finally {
      runInAction(() => (this.state = 'idle'));
    }
  }

  async install() {
    if (!this.available) return;
    this.state = 'installing';
    try {
      // The host restarts Wake once the new version is in place.
      await host.call('update.install');
    } catch (error) {
      runInAction(() => {
        this.error = String(error);
        this.state = 'idle';
      });
    }
  }
}

export const updater = new Updater();
