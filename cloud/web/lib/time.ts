/** "now", "4m", "2h", "3d": the Mac sidebar's compact timestamps. */
export function relative(iso: string | null, now: string) {
  if (!iso) return "";
  const minutes = Math.max(
    0,
    Math.round((Date.parse(now) - Date.parse(iso)) / 60_000),
  );
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.round(hours / 24)}d`;
}
