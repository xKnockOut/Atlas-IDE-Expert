unit Cm.E2569;

// E2569 Type parameter '%s' may need finalization - not allowed in variant record
// Erwartet: E2569

interface

type
  TVariante<T> = record
    case Integer of
      1: (Zahl: Integer);
      2: (Wert: T); // <- E2569
  end;

implementation

end.
