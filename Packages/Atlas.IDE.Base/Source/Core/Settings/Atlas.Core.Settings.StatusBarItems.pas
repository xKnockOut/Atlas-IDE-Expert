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
  cKnown: array[0..3] of string = (TAtlasStatusBarItems.Status, TAtlasStatusBarItems.Findings,
    TAtlasStatusBarItems.LiveCheck, TAtlasStatusBarItems.Method);

function RankOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cKnown) do
  begin
    if SameText(cKnown[mIndex], AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasStatusBarItems.All: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cKnown));
  for mIndex := 0 to High(cKnown) do
  begin
    Result[mIndex] := cKnown[mIndex];
  end;
end;

class function TAtlasStatusBarItems.DefaultText: string;
begin
  Result := Format(All);
end;

class function TAtlasStatusBarItems.Canonical(const AId: string): string;
var
  mRank: Integer;
begin
  mRank := RankOf(Trim(AId));
  if mRank < 0 then
  begin
    Exit('');
  end;
  Result := cKnown[mRank];
end;

class function TAtlasStatusBarItems.Contains(const AItems: TArray<string>; const AId: string): Boolean;
var
  mItem: string;
begin
  for mItem in AItems do
  begin
    if SameText(mItem, AId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasStatusBarItems.Parse(const AText: string): TArray<string>;
var
  mPart, mId: string;
begin
  Result := nil;
  for mPart in AText.Split([Delimiter]) do
  begin
    mId := Canonical(mPart);
    if (mId <> '') and not Contains(Result, mId) then
    begin
      Result := Result + [mId];
    end;
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
  mId: string;
  mIndex, mRank: Integer;
begin
  Result := Parse(Format(AItems));
  mId := Canonical(AId);
  if mId = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex] = mId then
    begin
      Delete(Result, mIndex, 1);
      Exit;
    end;
  end;
  mRank := RankOf(mId);
  mIndex := 0;
  while (mIndex <= High(Result)) and (RankOf(Result[mIndex]) < mRank) do
  begin
    Inc(mIndex);
  end;
  Insert(mId, Result, mIndex);
end;

end.
