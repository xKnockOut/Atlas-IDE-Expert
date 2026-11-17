unit Atlas.Core.Editor.MultiCursorSession;

// Ablauf mehrerer Einfügemarken (#589) über einen Editorpuffer
// (IAtlasEditSurface), ohne Open Tools API: Puffer, Text, Marken ([0] =
// Hauptmarke, also Cursor und Markierung der IDE) und die eigenen Schritte
// für Rückgängig und Wiederholen. Was sich an den Marken ändert, rechnet
// Atlas.Core.Editor.MultiCursor aus; hier geht es in den Puffer (ein
// Schreiber je Schritt, also ein Rückgängig-Schritt).
// - Vor jedem Schritt liest die Sitzung die Hauptmarke aus dem Puffer und
//   zieht eine Änderung nach, deren Meldung noch aussteht; danach setzt sie
//   die Hauptmarke.
// - BufferChanged: Steht der Text auf dem Stand vor bzw. nach einem eigenen
//   Schritt (Rückgängig, Wiederholen der IDE), kehren dessen Marken zurück.
//   Eine andere Änderung an der Hauptmarke führt sie an allen Marken aus
//   (Mirror, eigener Schritt), eine Änderung anderswo verschiebt die Marken.
// - Wechselt die Datei, endet die Sitzung.
// Tasten, Maus, Takt, Zwischenablage, Statusfeld und Zeichnen bleiben in der
// IDE (Atlas.IDE.Editor.MultiCursor), die über AOnFinish und AOnRefresh
// erfährt, wann die Marken enden bzw. neu gezeigt werden. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.MultiCursor,
  Atlas.Core.Editor.CaretSteps,
  Atlas.Core.Editor.EditSurface;

type
  TAtlasMultiCursorSession = class
  private
    FOnFinish: TProc;
    FOnRefresh: TProc;
    // Puffer, Text nach dem letzten bekannten Stand, Marken ([0] = Hauptmarke).
    FSurface: IAtlasEditSurface;
    FText: string;
    FLines: TArray<string>;
    FCarets: TAtlasCarets;
    FWriting: Boolean;
    FSteps: TAtlasCaretSteps;
    /// <summary>Text von ASurface und die Marken mit der Hauptmarke aus dem Puffer; False ohne Puffer oder bei
    /// schreibgeschütztem Puffer.</summary>
    function Prepare(const ASurface: IAtlasEditSurface; out AText: string): Boolean;
    procedure Apply(const AText, ANewText: string; const ACarets: TAtlasCarets);
    procedure SetCarets(const AText: string; const ACarets: TAtlasCarets);
    procedure WriteBuffer(const AText, ANewText: string);
    procedure SetText(const AText: string);
    /// <summary>Hauptmarke FCarets[0] in den Puffer.</summary>
    procedure WriteMain;
    /// <summary>Marken an AText anpassen (Rückgängig, Mirror, Shift).</summary>
    procedure Reconcile(const AText: string);
  public
    /// <summary>AOnFinish: Die Zusatzmarken sind zu Ende (Datei gewechselt); AOnRefresh: nach einem Schritt
    /// zeigen.</summary>
    constructor Create(const AOnFinish, AOnRefresh: TProc);
    /// <summary>Hauptmarke aus Cursor und Markierung von ASurface.</summary>
    class function MainOf(const ASurface: IAtlasEditSurface): TAtlasCaret; static;
    /// <summary>Mehr als eine Marke?</summary>
    function Active: Boolean;
    function Count: Integer;
    /// <summary>Datei der Marken; '' ohne.</summary>
    function FileName: string;
    function ShowsFile(const AFileName: string): Boolean;
    /// <summary>Alle Marken und Schritte vergessen; meldet AOnFinish, wenn Zusatzmarken bestanden.</summary>
    procedure Finish;
    /// <summary>Zeile ALine (0-basiert) im bekannten Stand; '' außerhalb.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>Der Puffer hat sich geändert: Marken nachziehen.</summary>
    procedure BufferChanged;
    /// <summary>Hauptmarke aus dem Puffer übernehmen, wenn sich der Text nicht geändert hat.</summary>
    procedure SyncMain;
    procedure DoEdit(const ASurface: IAtlasEditSurface; AKind: TAtlasCaretEditKind; const AInsert: string);
    /// <summary>Markierungen an allen Marken mit AOpen umschließen (#672, Zeichen AChars); False, wenn das
    /// Zeichen normal getippt wird.</summary>
    function DoWrap(const ASurface: IAtlasEditSurface; AOpen: Char; const AChars: string): Boolean;
    procedure DoMove(const ASurface: IAtlasEditSurface; AMove: TAtlasCaretMove; AExtend: Boolean);
    /// <summary>Markierte Texte aller Marken für die Zwischenablage; False ohne Markierung (Kopieren bleibt der
    /// IDE).</summary>
    function Selected(const ASurface: IAtlasEditSurface; out AText: string): Boolean;
    /// <summary>AClipboard an allen Marken einfügen (je Marke eine Zeile, wenn die Zahl passt).</summary>
    procedure DoPaste(const ASurface: IAtlasEditSurface; const AClipboard: string);
    procedure DoSkip(const ASurface: IAtlasEditSurface);
    /// <summary>Strg+D: Wort markieren bzw. nächstes Vorkommen hinzufügen; False gibt die Taste an die IDE.</summary>
    function Next(const ASurface: IAtlasEditSurface): Boolean;
    /// <summary>Marken an die Zeilenenden der Markierung; False ohne Markierung.</summary>
    function LineEnds(const ASurface: IAtlasEditSurface): Boolean;
    /// <summary>Marke in der Zeile darüber bzw. darunter.</summary>
    function Vertical(const ASurface: IAtlasEditSurface; AUp: Boolean): Boolean;
    /// <summary>Marke an ALine/ACharacter setzen bzw. entfernen; False, wenn AFileName nicht die Datei von
    /// ASurface ist.</summary>
    function Toggle(const ASurface: IAtlasEditSurface; const AFileName: string; ALine, ACharacter: Integer): Boolean;
    property Surface: IAtlasEditSurface read FSurface;
    property Carets: TAtlasCarets read FCarets;
    /// <summary>Schreibt die Sitzung gerade selbst in den Puffer?</summary>
    property Writing: Boolean read FWriting;
  end;

implementation

uses
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.WrapSelection;

{ TAtlasMultiCursorSession }

constructor TAtlasMultiCursorSession.Create(const AOnFinish, AOnRefresh: TProc);
begin
  inherited Create;
  FOnFinish := AOnFinish;
  FOnRefresh := AOnRefresh;
end;

class function TAtlasMultiCursorSession.MainOf(const ASurface: IAtlasEditSurface): TAtlasCaret;
var
  mAnchorLine, mAnchorCharacter, mLine, mCharacter: Integer;
begin
  ASurface.ReadSelection(mAnchorLine, mAnchorCharacter, mLine, mCharacter);
  if (mAnchorLine = mLine) and (mAnchorCharacter = mCharacter) then
  begin
    Result := TAtlasCaret.At(mLine, mCharacter);
  end
  else
  begin
    Result := TAtlasCaret.Range(mAnchorLine, mAnchorCharacter, mLine, mCharacter);
  end;
end;

function TAtlasMultiCursorSession.Prepare(const ASurface: IAtlasEditSurface; out AText: string): Boolean;
var
  mMain: TAtlasCaret;
begin
  Result := False;
  AText := '';
  if (ASurface = nil) or ASurface.IsReadOnly then
  begin
    Exit;
  end;
  if Active and not ShowsFile(ASurface.FileName) then
  begin
    Finish;
  end;
  AText := ASurface.Text;
  // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
  if Active and (AText <> FText) then
  begin
    Reconcile(AText);
    AText := FText;
  end;
  mMain := MainOf(ASurface);
  if Active then
  begin
    FCarets[0] := mMain;
    FCarets := TAtlasMultiCursor.Merge(FCarets);
  end
  else
  begin
    FCarets := [mMain];
    SetText(AText);
  end;
  FSurface := ASurface;
  Result := True;
end;

procedure TAtlasMultiCursorSession.Apply(const AText, ANewText: string; const ACarets: TAtlasCarets);
begin
  WriteBuffer(AText, ANewText);
  FSteps.Add(AText, ANewText, FCarets, ACarets);
  SetCarets(ANewText, ACarets);
end;

procedure TAtlasMultiCursorSession.SetCarets(const AText: string; const ACarets: TAtlasCarets);
begin
  FCarets := Copy(ACarets);
  SetText(AText);
  if Length(FCarets) > 0 then
  begin
    WriteMain;
  end;
  FOnRefresh();
end;

procedure TAtlasMultiCursorSession.WriteBuffer(const AText, ANewText: string);
var
  mStart, mOldLength: Integer;
  mInsert: string;
  mEdits: TAtlasTextEdits;
begin
  if not TAtlasLineMover.Difference(AText, ANewText, mStart, mOldLength, mInsert) then
  begin
    Exit;
  end;
  FWriting := True;
  try
    // Eine Ersetzung: ein Rückgängig-Schritt für alle Marken.
    mEdits := nil;
    SetLength(mEdits, 1);
    mEdits[0] := TAtlasTextEdit.Create(mStart, mOldLength, mInsert);
    FSurface.Write(AText, mEdits);
  finally
    FWriting := False;
  end;
end;

procedure TAtlasMultiCursorSession.SetText(const AText: string);
begin
  FText := AText;
  FLines := TAtlasMultiCursor.Lines(AText);
end;

procedure TAtlasMultiCursorSession.WriteMain;
begin
  FSurface.WriteSelection(FCarets[0].AnchorLine, FCarets[0].AnchorCharacter, FCarets[0].Line,
    FCarets[0].Character);
end;

function TAtlasMultiCursorSession.Active: Boolean;
begin
  Result := Length(FCarets) > 1;
end;

function TAtlasMultiCursorSession.Count: Integer;
begin
  Result := Length(FCarets);
end;

function TAtlasMultiCursorSession.FileName: string;
begin
  Result := TAtlasEditSurfaces.FileNameOf(FSurface);
end;

function TAtlasMultiCursorSession.ShowsFile(const AFileName: string): Boolean;
begin
  Result := (FSurface <> nil) and SameText(AFileName, FSurface.FileName);
end;

procedure TAtlasMultiCursorSession.Finish;
var
  mWas: Boolean;
begin
  mWas := Active;
  FCarets := nil;
  FSteps.Clear;
  FSurface := nil;
  FText := '';
  FLines := nil;
  if mWas then
  begin
    FOnFinish();
  end;
end;

function TAtlasMultiCursorSession.LineText(ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < Length(FLines)) then
  begin
    Result := FLines[ALine];
  end;
end;

procedure TAtlasMultiCursorSession.BufferChanged;
begin
  if Active and not FWriting then
  begin
    Reconcile(FSurface.Text);
  end;
end;

procedure TAtlasMultiCursorSession.Reconcile(const AText: string);
var
  mMirrored: string;
  mCarets: TAtlasCarets;
begin
  if not Active or (AText = FText) then
  begin
    Exit;
  end;
  // Rückgängig bzw. Wiederholen eines eigenen Schritts: dessen Marken.
  if FSteps.Recall(AText, mCarets) then
  begin
    FCarets := mCarets;
    SetText(AText);
    Exit;
  end;
  // Fremde Änderung: an der Hauptmarke an allen Marken ausführen, sonst die Marken verschieben.
  FSteps.Clear;
  if TAtlasMultiCursor.Mirror(FText, AText, FCarets, mMirrored, mCarets) then
  begin
    WriteBuffer(AText, mMirrored);
    SetText(mMirrored);
    FCarets := mCarets;
    WriteMain;
  end
  else
  begin
    FCarets := TAtlasMultiCursor.Shift(FText, AText, FCarets);
    SetText(AText);
  end;
end;

procedure TAtlasMultiCursorSession.SyncMain;
begin
  if not Active then
  begin
    Exit;
  end;
  FCarets[0] := MainOf(FSurface);
  FCarets := TAtlasMultiCursor.Merge(FCarets);
end;

procedure TAtlasMultiCursorSession.DoEdit(const ASurface: IAtlasEditSurface; AKind: TAtlasCaretEditKind;
  const AInsert: string);
var
  mText, mNewText: string;
  mCarets: TAtlasCarets;
begin
  if Prepare(ASurface, mText) and TAtlasMultiCursor.Edit(mText, FCarets, AKind, AInsert, mNewText, mCarets) then
  begin
    Apply(mText, mNewText, mCarets);
  end;
end;

function TAtlasMultiCursorSession.DoWrap(const ASurface: IAtlasEditSurface; AOpen: Char;
  const AChars: string): Boolean;
var
  mText: string;
  mWrapped: TAtlasWrapResult;
begin
  Result := TAtlasWrapSelection.Accepts(AOpen, AChars) and Prepare(ASurface, mText) and
    TAtlasWrapSelection.Wrap(TAtlasMultiCursor.Lines(mText), TAtlasCaretRanges.RangesOf(FCarets), AOpen, AChars,
    mWrapped);
  if Result then
  begin
    Apply(mText, string.Join(TAtlasMultiCursor.LineBreakOf(mText), mWrapped.Lines),
      TAtlasCaretRanges.CaretsOf(mWrapped.Selections));
  end;
end;

procedure TAtlasMultiCursorSession.DoMove(const ASurface: IAtlasEditSurface; AMove: TAtlasCaretMove;
  AExtend: Boolean);
var
  mText: string;
begin
  if Prepare(ASurface, mText) then
  begin
    SetCarets(mText, TAtlasMultiCursor.Move(FLines, FCarets, AMove, AExtend, ASurface.TabWidth));
  end;
end;

function TAtlasMultiCursorSession.Selected(const ASurface: IAtlasEditSurface; out AText: string): Boolean;
var
  mText: string;
begin
  AText := '';
  Result := Prepare(ASurface, mText);
  if Result then
  begin
    AText := TAtlasMultiCursor.SelectedText(mText, FCarets, TAtlasMultiCursor.LineBreakOf(mText));
    // Ohne Markierung bleibt Kopieren der IDE.
    Result := AText <> '';
  end;
end;

procedure TAtlasMultiCursorSession.DoPaste(const ASurface: IAtlasEditSurface; const AClipboard: string);
var
  mText, mNewText: string;
  mCarets: TAtlasCarets;
begin
  if (AClipboard <> '') and Prepare(ASurface, mText) and TAtlasMultiCursor.Paste(mText, FCarets, AClipboard,
    mNewText, mCarets) then
  begin
    Apply(mText, mNewText, mCarets);
  end;
end;

procedure TAtlasMultiCursorSession.DoSkip(const ASurface: IAtlasEditSurface);
var
  mText: string;
  mCarets: TAtlasCarets;
begin
  if not Prepare(ASurface, mText) or not TAtlasMultiCursor.SkipOccurrence(FLines, FCarets, False, False,
    mCarets) then
  begin
    Exit;
  end;
  SetCarets(mText, mCarets);
  if Length(mCarets) > 0 then
  begin
    ASurface.Reveal(mCarets[High(mCarets)].Line);
  end;
end;

function TAtlasMultiCursorSession.Next(const ASurface: IAtlasEditSurface): Boolean;
var
  mText: string;
  mCarets: TAtlasCarets;
  mWas: Boolean;
begin
  Result := False;
  mWas := Active;
  if not Prepare(ASurface, mText) then
  begin
    Exit;
  end;
  case TAtlasMultiCursor.NextOccurrence(FLines, FCarets, False, False, mCarets) of
    TAtlasOccurrence.WordSelected:
      begin
        FCarets := mCarets;
        WriteMain;
        ASurface.Paint;
        Result := True;
      end;
    TAtlasOccurrence.Added:
      begin
        SetCarets(mText, mCarets);
        ASurface.Reveal(mCarets[High(mCarets)].Line);
        Result := True;
      end;
  else
    // Kein Wort am Cursor: ohne Marken bekommt die IDE die Taste (Quelltext formatieren).
    Result := mWas;
    if not mWas then
    begin
      FCarets := nil;
    end;
  end;
end;

function TAtlasMultiCursorSession.LineEnds(const ASurface: IAtlasEditSurface): Boolean;
var
  mText: string;
begin
  Result := Prepare(ASurface, mText) and FCarets[0].HasSelection;
  if Result then
  begin
    SetCarets(mText, TAtlasMultiCursor.LineEnds(FLines, FCarets[0]));
    ASurface.Paint;
  end;
end;

function TAtlasMultiCursorSession.Vertical(const ASurface: IAtlasEditSurface; AUp: Boolean): Boolean;
var
  mText: string;
  mCarets: TAtlasCarets;
begin
  Result := Prepare(ASurface, mText) and TAtlasMultiCursor.AddVertical(FLines, FCarets, AUp, ASurface.TabWidth,
    mCarets);
  if Result then
  begin
    SetCarets(mText, mCarets);
    ASurface.Reveal(mCarets[High(mCarets)].Line);
  end;
end;

function TAtlasMultiCursorSession.Toggle(const ASurface: IAtlasEditSurface; const AFileName: string; ALine,
  ACharacter: Integer): Boolean;
var
  mText: string;
begin
  Result := Prepare(ASurface, mText) and SameText(AFileName, ASurface.FileName);
  if Result then
  begin
    SetCarets(mText, TAtlasMultiCursor.Toggle(FCarets, ALine, ACharacter));
    ASurface.Paint;
  end;
end;

end.
