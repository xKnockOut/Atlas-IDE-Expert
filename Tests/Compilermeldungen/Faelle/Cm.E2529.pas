unit Cm.E2529;

// E2529 Type parameters not allowed on operator
// Erwartet: E2529

interface

type
  TRec = record
    class operator Add<T>(A, B: TRec): TRec; // <- E2529
  end;

implementation

end.
