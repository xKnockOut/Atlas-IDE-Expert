unit Cm.E2474b;

// E2474 Record type required
// Erwartet: E2474
// Gegenprobe zu type-kind-required (#1370): Record-Helper für ein Interface.

interface

type
  IFoo = interface
  end;

  THelfer = record helper for IFoo // <- E2474
  end;

implementation

end.
