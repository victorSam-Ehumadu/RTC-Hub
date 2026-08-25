export function cn(...classes: (string | undefined | false | null)[]): string {
  return classes.filter(Boolean).join(' ');
}
export function timeAgo(date: string | Date): string {
  const seconds = Math.floor((Date.now() - new Date(date).getTime()) / 1000);
  if (seconds < 60) return 'just now';
  const intervals: [number, string][] = [
    [31536000,'year'],[2592000,'month'],[86400,'day'],[3600,'hour'],[60,'minute'],
  ];
  for (const [secs, label] of intervals) {
    const n = Math.floor(seconds / secs);
    if (n >= 1) return `${n} ${label}${n > 1 ? 's' : ''} ago`;
  }
  return 'just now';
}
export function getInitials(name: string): string {
  return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2);
}
export const ROLE_COLORS: Record<string, string> = {
  STUDENT: 'bg-blue-100 text-blue-700', ALUMNI: 'bg-purple-100 text-purple-700',
  BUSINESS: 'bg-green-100 text-green-700', ADMIN: 'bg-red-100 text-red-700',
};