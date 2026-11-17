unit Atlas.Core.Editor.LinkedSession;

// Ablauf einer Sitzung „Bezeichner live mitziehen“ (#658) über einen
// Editorpuffer (IAtlasEditSurface), ohne Open Tools API. Was eine Taste aus
// dem Namen macht und wie er in alle Vorkommen kommt, rechnet
// Atlas.Core.Editor.LinkedEditing; hier steht, was die Sitzung im Puffer tut:
// - Start: mit der Antwort des Servers, wenn sie noch zum Text passt und der
//   Cursor in einem Vorkommen steht (ohne Markierung, nicht schreibgeschützt).
// - Key: Taste im bearbeiteten Namen. Die erste schreibt die Umbenennung als
//   einen Rückgängig-Schritt; jede weitere nimmt den eigenen Schritt zurück
//   und schreibt die ganze Sitzung ab dem Stand zu Beginn neu. Strg+Z nimmt
//   so die Sitzung auf einmal zurück. Sieht der Puffer danach anders aus als
//   gerechnet, endet die Sitzung, ohne weiter zu schreiben.
// - BufferChanged: Hat die IDE den Namen selbst geändert (Einfügen, Vorschlag
//   übernommen), zieht die Sitzung die übrigen Vorkommen nach (eigener
//   Rückgängig-Schritt, ab dann einer je Taste); jede andere Änderung beendet
//   sie.
// - Check: Takt; Änderung nachziehen, deren Meldung aussteht, und enden, wenn
//   der Cursor den Namen verlassen hat.
// - Restore: Esc bei Konflikt stellt den alten Namen wieder her.
// Die IDE (Atlas.IDE.Editor.LinkedEditing) fragt den Server, fängt die Tasten
// ab, zeichnet und erfährt über AOnRefresh und AOnFinish, wann sie neu zeigen
// bzw. aufräumen muss. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.Core.Editor.EditSurface;

type
  /// <summary>Stand des Puffers, den die Sitzung kennt: Text, seine Zeilen und die Vorkommen darin. Die Arrays
  /// werden nie verändert, nur ersetzt.</summary>
  TAtlasLinkedState = record
    Text: string;
    Lines: TArray<string>;
    Ranges: TAtlasLinkedRanges;
    class function Create(const AText: string; const ARanges: TAtlasLinkedRanges): TAtlasLinkedState; static;
    /// <summary>Hat sich von Lines zu ALines höchstens Zeile ALine geändert?</summary>
    function OnlyLineChanged(const ALines: TArray<string>; ALine: Integer): Boolean;
  end;

  TAtlasLinkedSession = class
  private
    FOnRefresh: TProc;
    FOnFinish: TProc;
    FSurface: IAtlasEditSurface;
    // Bekannter Stand ([FPrimary] wird bearbeitet) und Stand zu Beginn samt altem Namen.
    FNow: TAtlasLinkedState;
    FStart: TAtlasLinkedState;
    FPrimary: Integer;
    FConflicts: TAtlasLinkedConflicts;
    FOriginal: string;
    // Der eigene Schritt oben in der Rückgängig-Liste enthält die ganze Sitzung.
    FGrouped: Boolean;
    FProblem: TAtlasLinkedProblem;
    FDetail: string;
    FWriting: Boolean;
    procedure UpdateProblem;
    /// <summary>Neuer Name und Cursorversatz für die Taste AKind am Cursor; False außerhalb des Namens oder wenn
    /// die Taste die Sitzung beendet.</summary>
    function NextName(AKind: TAtlasLinkedKey; const AInsert: string; out ANewName: string;
      out ANewOffset: Integer): Boolean;
    /// <summary>Eigenen Schritt zurücknehmen: ABase/ABaseRanges werden der Stand zu Beginn; sonst den letzten
    /// Stand wiederherstellen. False, wenn das nicht gelingt.</summary>
    function Rewind(var ABase: string; var ABaseRanges: TAtlasLinkedRanges): Boolean;
    /// <summary>ANewName ab ABase in alle Vorkommen schreiben und den Cursor setzen.</summary>
    function Apply(const ABase: string; const ABaseRanges: TAtlasLinkedRanges; const ANewName: string;
      ANewOffset: Integer): Boolean;
    /// <summary>Fremde Änderung: nur am bearbeiteten Namen, dann die übrigen nachziehen; sonst False.</summary>
    function Follow(const AText: string): Boolean;
    /// <summary>AName in die Bereiche ARanges von ABase schreiben (ein Schritt), ASkip ausgenommen.</summary>
    procedure WriteNames(const ABase: string; const ARanges: TAtlasLinkedRanges; const AName: string;
      ASkip: Integer);
    /// <summary>Alles vergessen, ohne zu melden.</summary>
    procedure Clear;
  public
    /// <summary>AOnRefresh: Stand nach einem Schritt zeigen; AOnFinish: Sitzung ist zu Ende.</summary>
    constructor Create(const AOnRefresh, AOnFinish: TProc);
    /// <summary>Ersetzungen, die AName in die Bereiche ARanges von ABase schreiben: aufsteigend, jeder Anfang
    /// einmal, ARanges[ASkip] ausgenommen (-1: keiner).</summary>
    class function Edits(const ABase: string; const ARanges: TAtlasLinkedRanges; const AName: string;
      ASkip: Integer): TAtlasTextEdits; static;
    function Active: Boolean;
    /// <summary>Datei der Sitzung; '' ohne.</summary>
    function FileName: string;
    function PrimaryRange: TAtlasLinkedRange;
    function PrimaryName: string;
    /// <summary>Zeilen des bekannten Stands.</summary>
    function Lines: TArray<string>;
    /// <summary>Vorkommen im bekannten Stand.</summary>
    function Ranges: TAtlasLinkedRanges;
    /// <summary>Sitzung auf ASurface beginnen mit der Antwort des Servers (Datei AFileName, Text AText);
    /// False, wenn sie nicht mehr zum Puffer passt oder der Cursor in keinem Vorkommen steht.</summary>
    function Start(const ASurface: IAtlasEditSurface; const AFileName, AText: string;
      const ARanges: TAtlasLinkedRanges; const AConflicts: TAtlasLinkedConflicts): Boolean;
    /// <summary>Taste im Namen auf ASurface (Ansicht derselben Datei) ausführen; False gibt sie an die IDE und
    /// beendet die Sitzung.</summary>
    function Key(const ASurface: IAtlasEditSurface; AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
    /// <summary>Takt mit Cursor und Text aus ASurface: ausstehende Änderung nachziehen, enden, wenn der Cursor
    /// den Namen verlassen hat.</summary>
    procedure Check(const ASurface: IAtlasEditSurface);
    /// <summary>Der Puffer hat sich geändert: der IDE am Namen folgen, sonst enden.</summary>
    procedure BufferChanged;
    /// <summary>Esc bei Konflikt: alten Namen wiederherstellen.</summary>
    procedure Restore;
    procedure Finish;
    property Primary: Integer read FPrimary;
    property Original: string read FOriginal;
    property Problem: TAtlasLinkedProblem read FProblem;
    /// <summary>Beschreibung des sichtbaren Namens bei Problem Visible.</summary>
    property Detail: string read FDetail;
    /// <summary>Schreibt die Sitzung gerade selbst in den Puffer?</summary>
    property Writing: Boolean read FWriting;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines;

{ TAtlasLinkedState }

class function TAtlasLinkedState.Create(const AText: string; const ARanges: TAtlasLinkedRanges): TAtlasLinkedState;
begin
  Result.Text := AText;
  Result.Lines := TTextLines.SplitLines(AText);
  Result.Ranges := Copy(ARanges);
end;

function TAtlasLinkedState.OnlyLineChanged(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(ALines) = Length(Lines);
  mIndex := 0;
  while Result and (mIndex <= High(ALines)) do
  begin
    Result := (mIndex = ALine) or (ALines[mIndex] = Lines[mIndex]);
    Inc(mIndex);
  end;
end;

{ TAtlasLinkedSession }

constructor TAtlasLinkedSession.Create(const AOnRefresh, AOnFinish: TProc);
begin
  inherited Create;
  FOnRefresh := AOnRefresh;
  FOnFinish := AOnFinish;
  Clear;
end;

class function TAtlasLinkedSession.Edits(const ABase: string; const ARanges: TAtlasLinkedRanges;
  const AName: string; ASkip: Integer): TAtlasTextEdits;
var
  mTable: TLineTable;
  mEdits: TList<TAtlasTextEdit>;
  mSeen: TDictionary<Integer, Boolean>;
  mIndex, mOffset: Integer;
begin
  mTable := TLineTable.Build(ABase);
  mEdits := TList<TAtlasTextEdit>.Create;
  mSeen := TDictionary<Integer, Boolean>.Create;
  try
    for mIndex := 0 to High(ARanges) do
    begin
      mOffset := mTable.LineStart(ARanges[mIndex].Line) + ARanges[mIndex].Character;
      if (mIndex <> ASkip) and not mSeen.ContainsKey(mOffset) then
      begin
        mSeen.Add(mOffset, True);
        mEdits.Add(TAtlasTextEdit.Create(mOffset, ARanges[mIndex].Length, AName));
      end;
    end;
    // Anfänge sind eindeutig: die Sortierung braucht keinen weiteren Schlüssel.
    mEdits.Sort(TComparer<TAtlasTextEdit>.Construct(
      function(const A, B: TAtlasTextEdit): Integer
      begin
        Result := A.Start - B.Start;
      end));
    Result := mEdits.ToArray;
  finally
    mSeen.Free;
    mEdits.Free;
  end;
end;

function TAtlasLinkedSession.Active: Boolean;
begin
  Result := Length(FNow.Ranges) > 0;
end;

function TAtlasLinkedSession.FileName: string;
begin
  Result := TAtlasEditSurfaces.FileNameOf(FSurface);
end;

function TAtlasLinkedSession.PrimaryRange: TAtlasLinkedRange;
begin
  Result := FNow.Ranges[FPrimary];
end;

function TAtlasLinkedSession.PrimaryName: string;
begin
  Result := TAtlasLinkedEditing.NameOf(FNow.Lines, PrimaryRange);
end;

function TAtlasLinkedSession.Lines: TArray<string>;
begin
  Result := FNow.Lines;
end;

function TAtlasLinkedSession.Ranges: TAtlasLinkedRanges;
begin
  Result := FNow.Ranges;
end;

procedure TAtlasLinkedSession.UpdateProblem;
begin
  FProblem := TAtlasLinkedEditing.Problem(PrimaryName, FOriginal, FConflicts, FDetail);
end;

function TAtlasLinkedSession.Start(const ASurface: IAtlasEditSurface; const AFileName, AText: string;
  const ARanges: TAtlasLinkedRanges; const AConflicts: TAtlasLinkedConflicts): Boolean;
var
  mText: string;
  mLine, mCharacter, mPrimary: Integer;
begin
  Result := (ASurface <> nil) and not ASurface.IsReadOnly and SameText(AFileName, ASurface.FileName) and
    not ASurface.HasSelection;
  if not Result then
  begin
    Exit;
  end;
  mText := ASurface.Text;
  ASurface.ReadCaret(mLine, mCharacter);
  mPrimary := TAtlasLinkedEditing.IndexAt(ARanges, mLine, mCharacter);
  Result := (mText = AText) and TAtlasLinkedEditing.Matches(TTextLines.SplitLines(mText), ARanges) and
    (mPrimary >= 0);
  if not Result then
  begin
    Exit;
  end;
  FSurface := ASurface;
  FPrimary := mPrimary;
  FConflicts := Copy(AConflicts);
  FStart := TAtlasLinkedState.Create(mText, ARanges);
  FNow := FStart;
  FOriginal := PrimaryName;
  FGrouped := False;
  FProblem := TAtlasLinkedProblem.None;
  FDetail := '';
end;

function TAtlasLinkedSession.Key(const ASurface: IAtlasEditSurface; AKind: TAtlasLinkedKey;
  const AInsert: string): Boolean;
var
  mText, mNewName, mBase: string;
  mNewOffset: Integer;
  mBaseRanges: TAtlasLinkedRanges;
begin
  Result := False;
  if not Active or (ASurface = nil) then
  begin
    Exit;
  end;
  if not SameText(ASurface.FileName, FileName) or ASurface.HasSelection then
  begin
    // Andere Datei, oder die Taste ersetzt eine Markierung: das bleibt der IDE.
    Finish;
    Exit;
  end;
  FSurface := ASurface;
  mText := ASurface.Text;
  if ((mText <> FNow.Text) and not Follow(mText)) or not NextName(AKind, AInsert, mNewName, mNewOffset) then
  begin
    Finish;
    Exit;
  end;
  // Direkt auf den eigenen Schritt: zurücknehmen und die ganze Sitzung als einen Schritt schreiben.
  mBase := FNow.Text;
  mBaseRanges := FNow.Ranges;
  if FGrouped and not Rewind(mBase, mBaseRanges) then
  begin
    // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
    Finish;
    Exit(True);
  end;
  Result := Apply(mBase, mBaseRanges, mNewName, mNewOffset);
end;

function TAtlasLinkedSession.NextName(AKind: TAtlasLinkedKey; const AInsert: string; out ANewName: string;
  out ANewOffset: Integer): Boolean;
var
  mLine, mCharacter: Integer;
  mRange: TAtlasLinkedRange;
begin
  ANewName := '';
  ANewOffset := 0;
  FSurface.ReadCaret(mLine, mCharacter);
  mRange := PrimaryRange;
  Result := mRange.Contains(mLine, mCharacter) and TAtlasLinkedEditing.Key(TAtlasLinkedEditing.NameOf(FNow.Lines,
    mRange), mCharacter - mRange.Character, AKind, AInsert, ANewName, ANewOffset);
end;

function TAtlasLinkedSession.Rewind(var ABase: string; var ABaseRanges: TAtlasLinkedRanges): Boolean;
begin
  if FSurface.Undo and (FSurface.Text = FStart.Text) then
  begin
    ABase := FStart.Text;
    ABaseRanges := FStart.Ranges;
    Exit(True);
  end;
  if FSurface.Text <> FNow.Text then
  begin
    FSurface.Redo;
  end;
  Result := FSurface.Text = FNow.Text;
end;

function TAtlasLinkedSession.Apply(const ABase: string; const ABaseRanges: TAtlasLinkedRanges;
  const ANewName: string; ANewOffset: Integer): Boolean;
var
  mNewText: string;
  mNewRanges: TAtlasLinkedRanges;
  mGrouped: Boolean;
begin
  Result := TAtlasLinkedEditing.Rename(ABase, ABaseRanges, ANewName, mNewText, mNewRanges);
  if not Result then
  begin
    Finish;
    Exit;
  end;
  // Ein Schritt ab dem Stand zu Beginn enthält die ganze Sitzung.
  mGrouped := ABase = FStart.Text;
  WriteNames(ABase, ABaseRanges, ANewName, -1);
  if FSurface.Text <> mNewText then
  begin
    // Der Puffer sieht anders aus als gerechnet: Sitzung beenden, nichts weiter schreiben.
    Finish;
    Exit;
  end;
  FGrouped := mGrouped;
  FNow := TAtlasLinkedState.Create(mNewText, mNewRanges);
  FSurface.WriteCaret(PrimaryRange.Line, PrimaryRange.Character + ANewOffset);
  UpdateProblem;
  FOnRefresh();
end;

function TAtlasLinkedSession.Follow(const AText: string): Boolean;
var
  mLines: TArray<string>;
  mLine: Integer;
  mName, mNewText: string;
  mRanges, mNewRanges: TAtlasLinkedRanges;
begin
  Result := Active;
  if not Result then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  mLine := PrimaryRange.Line;
  Result := FNow.OnlyLineChanged(mLines, mLine) and TAtlasLinkedEditing.Follow(FNow.Lines[mLine], mLines[mLine],
    PrimaryRange, mName) and TAtlasLinkedEditing.IsName(mName);
  if Result then
  begin
    mRanges := TAtlasLinkedEditing.Resized(FNow.Ranges, FPrimary, Length(mName));
    Result := TAtlasLinkedEditing.Rename(AText, mRanges, mName, mNewText, mNewRanges);
  end;
  if not Result then
  begin
    Exit;
  end;
  // Die Änderung der IDE liegt jetzt oben in der Rückgängig-Liste: ab hier ein Schritt je Taste.
  WriteNames(AText, mRanges, mName, FPrimary);
  Result := FSurface.Text = mNewText;
  if Result then
  begin
    FGrouped := False;
    FNow := TAtlasLinkedState.Create(mNewText, mNewRanges);
    UpdateProblem;
  end;
end;

procedure TAtlasLinkedSession.Check(const ASurface: IAtlasEditSurface);
var
  mLine, mCharacter: Integer;
begin
  if not Active or (ASurface = nil) then
  begin
    Exit;
  end;
  // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
  if ASurface.LineText(PrimaryRange.Line) <> FNow.Lines[PrimaryRange.Line] then
  begin
    BufferChanged;
  end;
  if not Active then
  begin
    Exit;
  end;
  // Cursor hat den Namen verlassen.
  ASurface.ReadCaret(mLine, mCharacter);
  if not PrimaryRange.Contains(mLine, mCharacter) then
  begin
    Finish;
  end;
end;

procedure TAtlasLinkedSession.BufferChanged;
var
  mText: string;
begin
  if not Active or FWriting then
  begin
    Exit;
  end;
  mText := FSurface.Text;
  if mText = FNow.Text then
  begin
    Exit;
  end;
  if Follow(mText) then
  begin
    FOnRefresh();
  end
  else
  begin
    Finish;
  end;
end;

procedure TAtlasLinkedSession.Restore;
begin
  if not Active then
  begin
    Exit;
  end;
  if FGrouped and (FSurface.Text = FNow.Text) and FSurface.Undo and (FSurface.Text = FStart.Text) then
  begin
    FNow := FStart;
    FSurface.WriteCaret(PrimaryRange.Line, PrimaryRange.EndCharacter);
    Exit;
  end;
  if FSurface.Text <> FNow.Text then
  begin
    FSurface.Redo;
  end;
  if FSurface.Text = FNow.Text then
  begin
    WriteNames(FNow.Text, FNow.Ranges, FOriginal, -1);
    FSurface.WriteCaret(PrimaryRange.Line, PrimaryRange.Character + Length(FOriginal));
  end;
end;

procedure TAtlasLinkedSession.WriteNames(const ABase: string; const ARanges: TAtlasLinkedRanges;
  const AName: string; ASkip: Integer);
begin
  FWriting := True;
  try
    FSurface.Write(ABase, Edits(ABase, ARanges, AName, ASkip));
  finally
    FWriting := False;
  end;
end;

procedure TAtlasLinkedSession.Clear;
begin
  FSurface := nil;
  FNow := Default(TAtlasLinkedState);
  FStart := Default(TAtlasLinkedState);
  FPrimary := -1;
  FConflicts := nil;
  FOriginal := '';
  FGrouped := False;
  FProblem := TAtlasLinkedProblem.None;
  FDetail := '';
end;

procedure TAtlasLinkedSession.Finish;
var
  mWas: Boolean;
begin
  mWas := Active;
  Clear;
  if mWas then
  begin
    FOnFinish();
  end;
end;

end.
