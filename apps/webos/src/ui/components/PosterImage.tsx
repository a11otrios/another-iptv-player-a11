import { useEffect, useRef, useState } from "react";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { useTabActive } from "./TabLayer";
import { useCachedImage } from "../../services/imageCache";

// Lazy poster loader for TV memory budgets: the real src is only assigned
// when the element approaches the viewport (IntersectionObserver, Chrome 51+)
// and is released again once it drifts far off-screen. The URL resolves
// through the two-tier image cache (memory + IndexedDB blobs).
//
// Covered layers are the exception: a display:none screen OR hidden tab
// reports "not intersecting" too, but releasing there would rebuild every
// poster on return (looks like a full page reload). While the layer is
// inactive the loaded state is frozen; releases only happen from real
// scrolling.

const observed = new WeakMap<Element, (visible: boolean) => void>();
let sharedObserver: IntersectionObserver | null = null;

function observer(): IntersectionObserver {
  if (!sharedObserver) {
    sharedObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          observed.get(entry.target)?.(entry.isIntersecting);
        }
      },
      { rootMargin: "600px" },
    );
  }
  return sharedObserver;
}

export function PosterImage({
  src,
  alt,
  className,
  eager = false,
}: {
  src?: string;
  alt: string;
  className?: string;
  eager?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [failed, setFailed] = useState(false);
  const screenActive = useScreenActive();
  const tabActive = useTabActive();
  const layerActive = screenActive && tabActive;
  const layerActiveRef = useRef(layerActive);
  layerActiveRef.current = layerActive;

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    // Chromium 53 can miss the initial IntersectionObserver callback for
    // elements beneath a GPU-transformed shelf. Prime cards that are already
    // near the viewport from their actual layout geometry.
    const frame = window.requestAnimationFrame(() => {
      if (isNearViewport(el)) setVisible(true);
    });
    observed.set(el, (isVisible: boolean) => {
      // Never RELEASE while the layer is covered; becoming visible is
      // always accepted.
      if (!isVisible && !layerActiveRef.current) return;
      setVisible(isVisible);
    });
    observer().observe(el);
    return () => {
      window.cancelAnimationFrame(frame);
      observed.delete(el);
      observer().unobserve(el);
    };
  }, []);

  useEffect(() => {
    if (eager) setVisible(true);
  }, [eager]);

  const resolved = useCachedImage(src, visible || eager);
  // Fade the artwork in once decoded — hard pops read as "instant loading".
  const [loaded, setLoaded] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);
  const showImage = (visible || eager) && !!resolved && !failed;
  useEffect(() => {
    // Already-cached images can complete before React's onLoad listener sees
    // the event (e.g. remounting after Back) — without this check they would
    // sit at opacity 0 forever.
    const img = imgRef.current;
    setFailed(false);
    setLoaded(!!img && img.complete && img.naturalWidth > 0);
  }, [resolved, visible, eager]);

  return (
    <div
      ref={ref}
      className={`poster-image ${className ?? ""}`}
      data-image-source={src ? "present" : "missing"}
      data-image-state={failed ? "failed" : loaded ? "loaded" : showImage ? "loading" : "waiting"}
    >
      {showImage ? (
        <img
          ref={imgRef}
          src={resolved}
          alt={alt}
          loading="lazy"
          className={loaded ? "loaded" : undefined}
          onLoad={() => setLoaded(true)}
          onError={() => setFailed(true)}
        />
      ) : (
        <div className="poster-fallback">{alt.slice(0, 2).toUpperCase()}</div>
      )}
    </div>
  );
}

function isNearViewport(element: Element, margin = 600): boolean {
  const rect = element.getBoundingClientRect();
  const width = window.innerWidth || document.documentElement.clientWidth;
  const height = window.innerHeight || document.documentElement.clientHeight;
  return (
    rect.right >= -margin &&
    rect.left <= width + margin &&
    rect.bottom >= -margin &&
    rect.top <= height + margin
  );
}
