unit Atlas.Core.Editor.NavHistory;

// Navigationsverlauf über Dateien hinweg (#504), Teil ohne VCL und Open Tools
// API:
//   - Sprung: andere Datei oder mehr als JumpLines Zeilen (wie VS Code). Die
//     Ausgangsstelle kommt auf den Zurück-Stapel, der Vor-Stapel leert sich.
//   - Zurück/Vor wie im Browser: die aktuelle Stelle wandert auf den anderen
//     Stapel.
//   - Bearbeitungsstellen: eigener Verlauf; eine Änderung höchstens
//     EditMergeLines Zeilen neben der letzten in derselben Datei ersetzt diese.
//     „Letzte Bearbeitungsstelle“ geht bei jedem Aufruf eine weiter zurück,
//     eine neue Änderung beginnt wieder vorn.
//   - Zeilen einfügen oder löschen verschiebt alle Einträge der Datei unterhalb
//     der Stelle; Einträge in gelöschten Zeilen rücken an die Stelle.
//   - Höchstens MaxEntries Einträge je Verlauf, nur für die laufende Sitzung.
// Zeilen und Spalten 1-basiert wie im Editor.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasNavPlace = record
    FileName: string;
    Line: Integer;
    Column: Integer;
    /// <summary>Text der Zeile (gekürzt) beim Merken.</summary>
    Excerpt: string;
    Time: TDateTime;
    class function Create(const AFileName: string; ALine, AColumn: Integer): TAtlasNavPlace; static;
    function SameLine(const AOther: TAtlasNavPlace): Boolean;
  end;

{$SCOPEDENUMS ON}
  TAtlasNavKind = (Back, Ahead, Edit);
{$SCOPEDENUMS OFF}

  TAtlasNavListEntry = record
    Kind: TAtlasNavKind;
    /// <summary>Index im jeweiligen Verlauf (für Jump).</summary>
    Index: Integer;
    Place: TAtlasNavPlace;
  end;

  TAtlasNavHistory = class
  public const
    MaxEntries = 100;
    JumpLines = 10;
    EditMergeLines = 3;
    MaxExcerpt = 80;
  private
    FBack: TList<TAtlasNavPlace>;
    FForward: TList<TAtlasNavPlace>;
    FEdits: TList<TAtlasNavPlace>;
    /// <summary>Wie weit „Letzte Bearbeitungsstelle“ zurückgegangen ist; -1 = noch nicht.</summary>
    FEditCursor: Integer;
    class procedure Push(AList: TList<TAtlasNavPlace>; const APlace: TAtlasNavPlace); static;
    class procedure ShiftList(AList: TList<TAtlasNavPlace>; const AFileName: string; AAnchor, ADelta: Integer);
      static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ist der Weg von AFrom nach ATo ein Sprung?</summary>
    class function IsJump(const AFrom, ATo: TAtlasNavPlace): Boolean; static;
    /// <summary>Auszug für die Liste: getrimmt, Tabs als Leerzeichen, höchstens MaxExcerpt Zeichen.</summary>
    class function Excerpt(const ALineText: string): string; static;
    /// <summary>Der Cursor ist von AFrom nach ATo gesprungen (IsJump prüft der Aufrufer oder hier: ohne Sprung
    /// geschieht nichts).</summary>
    procedure Jumped(const AFrom, ATo: TAtlasNavPlace);
    /// <summary>Ziel für „Zurück“ von ACurrent aus; False ohne Verlauf.</summary>
    function StepBack(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
    /// <summary>Ziel für „Vor“; False ohne Verlauf.</summary>
    function StepForward(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
    /// <summary>An APlace wurde geändert.</summary>
    procedure Edited(const APlace: TAtlasNavPlace);
    /// <summary>Ziel für „Letzte Bearbeitungsstelle“: zuerst die jüngste Änderung, die nicht an ACurrent liegt,
    /// bei weiteren Aufrufen die davor (zuletzt bleibt es bei der ältesten). False ohne Änderung.</summary>
    function LastEdit(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
    /// <summary>In AFileName wurden ab Zeile AAnchor ADelta Zeilen eingefügt (&gt; 0) bzw. gelöscht (&lt; 0):
    /// Einträge unterhalb verschieben sich.</summary>
    procedure LinesChanged(const AFileName: string; AAnchor, ADelta: Integer);
    /// <summary>Einträge für die Liste: Vor-Stapel (fernster zuerst), Zurück-Stapel (jüngster zuerst), dann die
    /// Bearbeitungsstellen (jüngste zuerst).</summary>
    function Entries: TArray<TAtlasNavListEntry>;
    /// <summary>Zu einem Eintrag aus Entries springen: der Verlauf wird bis dorthin zurück- bzw. vorgespult.
    /// Bearbeitungsstellen zählen als neuer Sprung.</summary>
    function Jump(const AEntry: TAtlasNavListEntry; const ACurrent: TAtlasNavPlace;
      out ATarget: TAtlasNavPlace): Boolean;
    function BackCount: Integer;
    function ForwardCount: Integer;
    function EditCount: Integer;
    procedure Clear;
  end;

implementation

uses
  System.Math;

{ TAtlasNavPlace }

class function TAtlasNavPlace.Create(const AFileName: string; ALine, AColumn: Integer): TAtlasNavPlace;
begin
  Result := Default(TAtlasNavPlace);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
end;

function TAtlasNavPlace.SameLine(const AOther: TAtlasNavPlace): Boolean;
begin
  Result := (Line = AOther.Line) and SameText(FileName, AOther.FileName);
end;

{ TAtlasNavHistory }

constructor TAtlasNavHistory.Create;
begin
  inherited Create;
  FBack := TList<TAtlasNavPlace>.Create;
  FForward := TList<TAtlasNavPlace>.Create;
  FEdits := TList<TAtlasNavPlace>.Create;
  FEditCursor := -1;
end;

destructor TAtlasNavHistory.Destroy;
begin
  FEdits.Free;
  FForward.Free;
  FBack.Free;
  inherited;
end;

class function TAtlasNavHistory.IsJump(const AFrom, ATo: TAtlasNavPlace): Boolean;
begin
  if (AFrom.FileName = '') or (ATo.FileName = '') then
    Exit(False);
  Result := not SameText(AFrom.FileName, ATo.FileName) or (Abs(ATo.Line - AFrom.Line) > JumpLines);
end;

class function TAtlasNavHistory.Excerpt(const ALineText: string): string;
begin
  Result := Trim(ALineText.Replace(#9, ' '));
  if Length(Result) > MaxExcerpt then
    Result := Copy(Result, 1, MaxExcerpt - 1) + '…';
end;

class procedure TAtlasNavHistory.Push(AList: TList<TAtlasNavPlace>; const APlace: TAtlasNavPlace);
begin
  if (AList.Count > 0) and AList.Last.SameLine(APlace) then
    AList[AList.Count - 1] := APlace
  else
    AList.Add(APlace);
  while AList.Count > MaxEntries do
    AList.Delete(0);
end;

procedure TAtlasNavHistory.Jumped(const AFrom, ATo: TAtlasNavPlace);
begin
  if not IsJump(AFrom, ATo) then
    Exit;
  Push(FBack, AFrom);
  FForward.Clear;
end;

function TAtlasNavHistory.StepBack(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
begin
  Result := FBack.Count > 0;
  if not Result then
    Exit;
  ATarget := FBack.Last;
  FBack.Delete(FBack.Count - 1);
  if ACurrent.FileName <> '' then
    Push(FForward, ACurrent);
end;

function TAtlasNavHistory.StepForward(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
begin
  Result := FForward.Count > 0;
  if not Result then
    Exit;
  ATarget := FForward.Last;
  FForward.Delete(FForward.Count - 1);
  if ACurrent.FileName <> '' then
    Push(FBack, ACurrent);
end;

procedure TAtlasNavHistory.Edited(const APlace: TAtlasNavPlace);
begin
  FEditCursor := -1;
  if (FEdits.Count > 0) and SameText(FEdits.Last.FileName, APlace.FileName) and
    (Abs(FEdits.Last.Line - APlace.Line) <= EditMergeLines) then
  begin
    FEdits[FEdits.Count - 1] := APlace;
    Exit;
  end;
  FEdits.Add(APlace);
  while FEdits.Count > MaxEntries do
    FEdits.Delete(0);
end;

function TAtlasNavHistory.LastEdit(const ACurrent: TAtlasNavPlace; out ATarget: TAtlasNavPlace): Boolean;
var
  Index: Integer;
begin
  Result := FEdits.Count > 0;
  if not Result then
    Exit;
  if FEditCursor < 0 then
  begin
    // Erster Aufruf: die jüngste Änderung, außer der Cursor steht schon dort.
    Index := FEdits.Count - 1;
    if FEdits[Index].SameLine(ACurrent) and (Index > 0) then
      Dec(Index);
  end
  else
    Index := Max(0, FEditCursor - 1);
  FEditCursor := Index;
  ATarget := FEdits[Index];
end;

class procedure TAtlasNavHistory.ShiftList(AList: TList<TAtlasNavPlace>; const AFileName: string;
  AAnchor, ADelta: Integer);
var
  Index: Integer;
  Place: TAtlasNavPlace;
begin
  for Index := 0 to AList.Count - 1 do
  begin
    Place := AList[Index];
    if not SameText(Place.FileName, AFileName) or (Place.Line <= AAnchor) then
      Continue;
    if (ADelta < 0) and (Place.Line <= AAnchor - ADelta) then
      // In den gelöschten Zeilen: an die Stelle der Löschung.
      Place.Line := AAnchor
    else
      Place.Line := Place.Line + ADelta;
    AList[Index] := Place;
  end;
end;

procedure TAtlasNavHistory.LinesChanged(const AFileName: string; AAnchor, ADelta: Integer);
begin
  if ADelta = 0 then
    Exit;
  ShiftList(FBack, AFileName, AAnchor, ADelta);
  ShiftList(FForward, AFileName, AAnchor, ADelta);
  ShiftList(FEdits, AFileName, AAnchor, ADelta);
end;

function TAtlasNavHistory.Entries: TArray<TAtlasNavListEntry>;
var
  Index: Integer;
  Entry: TAtlasNavListEntry;
begin
  Result := nil;
  for Index := 0 to FForward.Count - 1 do
  begin
    Entry.Kind := TAtlasNavKind.Ahead;
    Entry.Index := Index;
    Entry.Place := FForward[Index];
    Result := Result + [Entry];
  end;
  for Index := FBack.Count - 1 downto 0 do
  begin
    Entry.Kind := TAtlasNavKind.Back;
    Entry.Index := Index;
    Entry.Place := FBack[Index];
    Result := Result + [Entry];
  end;
  for Index := FEdits.Count - 1 downto 0 do
  begin
    Entry.Kind := TAtlasNavKind.Edit;
    Entry.Index := Index;
    Entry.Place := FEdits[Index];
    Result := Result + [Entry];
  end;
end;

function TAtlasNavHistory.Jump(const AEntry: TAtlasNavListEntry; const ACurrent: TAtlasNavPlace;
  out ATarget: TAtlasNavPlace): Boolean;
var
  Current, Next: TAtlasNavPlace;
begin
  Result := False;
  Current := ACurrent;
  case AEntry.Kind of
    TAtlasNavKind.Back:
      begin
        if (AEntry.Index < 0) or (AEntry.Index >= FBack.Count) then
          Exit;
        // Zurückspulen: alles über dem Eintrag wandert auf den Vor-Stapel.
        while (FBack.Count > AEntry.Index + 1) and StepBack(Current, Next) do
          Current := Next;
        Result := StepBack(Current, ATarget);
      end;
    TAtlasNavKind.Ahead:
      begin
        if (AEntry.Index < 0) or (AEntry.Index >= FForward.Count) then
          Exit;
        while (FForward.Count > AEntry.Index + 1) and StepForward(Current, Next) do
          Current := Next;
        Result := StepForward(Current, ATarget);
      end;
    TAtlasNavKind.Edit:
      begin
        if (AEntry.Index < 0) or (AEntry.Index >= FEdits.Count) then
          Exit;
        ATarget := FEdits[AEntry.Index];
        Jumped(ACurrent, ATarget);
        Result := True;
      end;
  end;
end;

function TAtlasNavHistory.BackCount: Integer;
begin
  Result := FBack.Count;
end;

function TAtlasNavHistory.ForwardCount: Integer;
begin
  Result := FForward.Count;
end;

function TAtlasNavHistory.EditCount: Integer;
begin
  Result := FEdits.Count;
end;

procedure TAtlasNavHistory.Clear;
begin
  FBack.Clear;
  FForward.Clear;
  FEdits.Clear;
  FEditCursor := -1;
end;

end.
