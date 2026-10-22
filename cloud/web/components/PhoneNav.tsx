import Link from "next/link";
import styles from "./PhoneNav.module.css";

/** Phone-width stand-in for the rail's Today / Desks rows. Hidden on wider screens. */
export function PhoneNav({ current }: { current: "today" | "desks" }) {
  return (
    <nav className={styles.nav} aria-label="Sections">
      <Link href="/" aria-current={current === "today" ? "page" : undefined}>
        Today
      </Link>
      <Link
        href="/desks"
        aria-current={current === "desks" ? "page" : undefined}
      >
        Desks
      </Link>
    </nav>
  );
}
