unit Atlas.Core.Settings.StatusBarItems;

// Atlas-Statusleiste (#1155), Belegung ohne VCL und OTA. Gehört zu den
// Einstellungen, weil der Parser (Atlas.Core.Settings.Plugin) die Liste
// bereinigt.
// - editor.statusBar.items ist die Liste der sichtbaren Elemente in
//   Reihenfolge, durch Komma getrennt: status, findings, liveCheck, method.
// - Parse liest nur bekannte Elemente (ohne Groß-/Kleinschreibung, in der
//   Schreibweise oben), jedes höchstens einmal; Normalize schreibt die Liste in
//   dieser Form. Eine leere Liste bleibt leer (alle Elemente aus).
// - Toggle ist der Schritt im Menü „Leiste anpassen“: Ein sichtbares Element
//   verschwindet, ein ausgeblendetes kommt an seine Stelle nach der Vorgabe
//   zurück (vor das erste vorhandene, das in der Vorgabe nach ihm steht).

interface

uses
  System.SysUtils;

type
  TAtlasStatusBarItems = class
  public const
    Delimiter = ',';
    Status = 'status';
    Findings = 'findings';
    LiveCheck = 'liveCheck';
    Method = 'method';
  public
    /// <summary>Alle Elemente in der Vorgabe-Reihenfolge.</summary>
    class function All: TArray<string>; static;
    /// <summary>Vorgabe als Text: alle Elemente.</summary>
    class function DefaultText: string; static;
    /// <summary>Bekanntes Element? AId in Schreibweise der Konstanten; '' sonst.</summary>
    class function Canonical(const AId: string): string; static;
    /// <summary>Bekannte Elemente in Reihenfolge, jedes einmal; Unbekanntes und Leerraum fallen weg.</summary>
    class function Parse(const AText: string): TArray<string>; static;
    class function Format(const AItems: TArray<string>): string; static;
    /// <summary>Format über Parse.</summary>
    class function Normalize(const AText: string): string; static;
    class function Contains(const AItems: TArray<string>; const AId: string): Boolean; static;
    /// <summary>AId aus- bzw. an seiner Vorgabe-Stelle wieder einblenden.</summary>
    class function Toggle(const AItems: TArray<string>; const AId: string): TArray<string>; static;
  end;

implementation

const
  Known: array[0..3] of string = (TAtlasStatusBarItems.Status, TAtlasStatusBarItems.Findings,
    TAtlasStatusBarItems.LiveCheck, TAtlasStatusBarItems.Method);

function RankOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Known) do
    if SameText(Known[Index], AId) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasStatusBarItems.All: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Known));
  for Index := 0 to High(Known) do
    Result[Index] := Known[Index];
end;

class function TAtlasStatusBarItems.DefaultText: string;
begin
  Result := Format(All);
end;

class function TAtlasStatusBarItems.Canonical(const AId: string): string;
var
  Rank: Integer;
begin
  Rank := RankOf(Trim(AId));
  if Rank < 0 then
    Exit('');
  Result := Known[Rank];
end;

class function TAtlasStatusBarItems.Contains(const AItems: TArray<string>; const AId: string): Boolean;
var
  Item: string;
begin
  for Item in AItems do
    if SameText(Item, AId) then
      Exit(True);
  Result := False;
end;

class function TAtlasStatusBarItems.Parse(const AText: string): TArray<string>;
var
  Part, Id: string;
begin
  Result := nil;
  for Part in AText.Split([Delimiter]) do
  begin
    Id := Canonical(Part);
    if (Id <> '') and not Contains(Result, Id) then
      Result := Result + [Id];
  end;
end;

class function TAtlasStatusBarItems.Format(const AItems: TArray<string>): string;
begin
  Result := string.Join(Delimiter, AItems);
end;

class function TAtlasStatusBarItems.Normalize(const AText: string): string;
begin
  Result := Format(Parse(AText));
end;

class function TAtlasStatusBarItems.Toggle(const AItems: TArray<string>; const AId: string): TArray<string>;
var
  Id: string;
  Index, Rank: Integer;
begin
  Result := Parse(Format(AItems));
  Id := Canonical(AId);
  if Id = '' then
    Exit;
  for Index := 0 to High(Result) do
    if Result[Index] = Id then
    begin
      Delete(Result, Index, 1);
      Exit;
    end;
  Rank := RankOf(Id);
  Index := 0;
  while (Index <= High(Result)) and (RankOf(Result[Index]) < Rank) do
    Inc(Index);
  Insert(Id, Result, Index);
end;

end.
