unit Atlas.Core.Files.Entries;

// Ein Objekt je Datei, ohne VCL und Open Tools API: Ablagen, die Daten je Datei halten (Inlay-Hints,
// Probleme …), schlagen über den Dateinamen ohne Groß-/Kleinschreibung nach.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Objekte je Datei; der Schlüssel ist der Dateiname ohne Groß-/Kleinschreibung. Mit
  /// [doOwnsValues] anlegen, wenn die Ablage die Objekte besitzt.</summary>
  TAtlasFileEntries<T: class> = class(TObjectDictionary<string, T>)
  public
    /// <summary>Schlüssel zu AFileName.</summary>
    class function Key(const AFileName: string): string; static;
    /// <summary>Objekt zu AFileName; nil ohne Eintrag.</summary>
    function Find(const AFileName: string): T;
    /// <summary>AEntry als Objekt zu AFileName aufnehmen (es darf noch keins geben).</summary>
    procedure Put(const AFileName: string; AEntry: T);
    /// <summary>Eintrag zu AFileName entfernen (besitzt die Ablage das Objekt, wird es freigegeben).</summary>
    procedure Drop(const AFileName: string);
  end;

implementation

{ TAtlasFileEntries<T> }

class function TAtlasFileEntries<T>.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TAtlasFileEntries<T>.Find(const AFileName: string): T;
begin
  if not TryGetValue(Key(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

procedure TAtlasFileEntries<T>.Put(const AFileName: string; AEntry: T);
begin
  Add(Key(AFileName), AEntry);
end;

procedure TAtlasFileEntries<T>.Drop(const AFileName: string);
begin
  Remove(Key(AFileName));
end;

end.
