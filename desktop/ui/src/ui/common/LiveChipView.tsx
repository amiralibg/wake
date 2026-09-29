// A live chip as a small capsule (LiveChipView.swift): icon and text in the chip's
// tone, and for media a hairline of progress along the bottom.

import { ArrowDown, ArrowUp, CircleCheck, CircleDashed, CircleX, Mail, OctagonAlert, Pause, RefreshCw, Tag, TriangleAlert, Volume2 } from 'lucide-react';
import type { LiveChip } from '../../model/live';

const ICONS: Record<string, typeof Tag> = {
  'triangle-alert': TriangleAlert,
  'circle-check': CircleCheck,
  'circle-x': CircleX,
  'circle-dashed': CircleDashed,
  'octagon-alert': OctagonAlert,
  'arrow-down': ArrowDown,
  'arrow-up': ArrowUp,
  tag: Tag,
  mail: Mail,
  'volume-2': Volume2,
  pause: Pause,
  'refresh-cw': RefreshCw,
};

export function LiveChipView({ chip }: { chip: LiveChip }) {
  const Icon = ICONS[chip.icon] ?? Tag;
  return (
    <span className={`chip tone-${chip.tone}`} title={chip.text}>
      <Icon size={9} strokeWidth={2.8} />
      <span className="chip-text">{chip.text}</span>
      {chip.progress != null && <span className="chip-progress" style={{ width: `calc((100% - 12px) * ${Math.max(0.02, chip.progress)})` }} />}
    </span>
  );
}
