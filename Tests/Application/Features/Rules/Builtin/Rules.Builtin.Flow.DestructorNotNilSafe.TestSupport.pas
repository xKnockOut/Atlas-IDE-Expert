unit Rules.Builtin.Flow.DestructorNotNilSafe.TestSupport;

// Gemeinsame Hilfen der Tests zu destructor-not-nil-safe (Regel und Auswertung der Konstruktoren).

interface

/// <summary>Unit mit TImport (Felder FStrom und FZeilen), dem Konstruktor-Rumpf AConstructor und dem
/// Destruktor-Rumpf ADestructor.</summary>
function ImportUnit(const AConstructor, ADestructor: string): string;

implementation

function ImportUnit(const AConstructor, ADestructor: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FStrom: TFileStream;'#10 +
    '    FZeilen: TStringList;'#10'  public'#10'    constructor Create(const Datei: string);'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'constructor TImport.Create(const Datei: string);'#10'begin'#10 + AConstructor + #10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10 + ADestructor + #10'end;'#10'end.';
end;

end.
