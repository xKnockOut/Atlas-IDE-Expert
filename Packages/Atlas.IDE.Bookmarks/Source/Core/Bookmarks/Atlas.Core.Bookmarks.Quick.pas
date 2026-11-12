unit Atlas.Core.Bookmarks.Quick;

// Schnelle Lesezeichen (#1104), ohne VCL und Open Tools API: die Befehle auf
// der gemeinsamen Liste der Lesezeichen (TAtlasBookmarkList, #622).
// - Spalte links der Zeilennummern: Dort stehen die schnellen Lesezeichen
//   (Art Quick) und jedes nummerierte (InColumn). Mehrere an einer Zeile:
//   die kleinste Nummer vorn, unnummerierte dahinter (ColumnMarks).
// - Klick in die Spalte (Click): freier Platz setzt ein unnummeriertes
//   Lesezeichen, ein Marker entfernt die Marker der Zeile (schnelle ganz,
//   benannte verlieren nur ihre Nummer).
// - Strg+Umschalt+N (SetNumber): Nummer N in der Zeile; steht N schon dort,
//   wird es entfernt, steht N woanders (auch in einer anderen Datei), zieht
//   es hierher um. Jede Nummer gibt es je Liste höchstens einmal.
// - Strg+Umschalt+K (Toggle): unnummeriertes Lesezeichen setzen bzw.
//   entfernen, beliebig viele je Datei.
// - Strg+N (Jump): Ziel projektweit oder nur in der aktuellen Datei.
// - Nächstes/voriges Lesezeichen (Step): reihum in der Datei über alle
//   gefundenen Lesezeichen.
// - Übernahme der IDE-Lesezeichen 1–9 beim ersten Öffnen (Import): Ist die
//   Nummer bei Atlas schon vergeben, kommt das IDE-Lesezeichen unnummeriert
//   dazu, damit nichts verloren geht.
// - Faltungsakkorde (Chord): Strg+Umschalt+K ist in der IDE der erste Teil
//   der Faltungsakkorde (Strg+Umschalt+K, dann U, E, A, T, O …). Atlas wartet
//   chordWait ms; ein Faltungsbuchstabe geht mit dem ersten Teil an die IDE,
//   Zeitüberschreitung oder eine andere Taste setzt bzw. entfernt das
//   Lesezeichen.
// - Tasten für 1–9 (KeyFor, NumberOfKey): eine Grundtaste für die 1 (etwa
//   Strg+Umschalt+1), 2–9 mit denselben Umschalttasten.

interface

uses
  System.SysUtils,
  Atlas.Core.Bookmarks.Store;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was ein Befehl an der Liste geändert hat.</summary>
  TAtlasQuickChange = (None, Added, Moved, Removed);
  /// <summary>Strg+1…9: projektweit oder nur in der aktuellen Datei (bookmarks.quick.scope).</summary>
  TAtlasQuickScope = (Project, CurrentFile);
  /// <summary>Found: Ziel bekannt (kann „nicht gefunden“ sein, dann letzte bekannte Zeile); NotAssigned: Nummer
  /// frei; OtherFile: Nummer steht in einer anderen Datei, der Bereich ist aber die aktuelle Datei.</summary>
  TAtlasQuickJump = (Found, NotAssigned, OtherFile);
  /// <summary>Wait: weiter auf den zweiten Akkordteil warten; Toggle: Lesezeichen setzen bzw. entfernen;
  /// PassOn: Strg+Umschalt+K und die Taste an die Faltung der IDE weiterreichen.</summary>
  TAtlasChordAction = (Wait, Toggle, PassOn);
  {$SCOPEDENUMS OFF}

  /// <summary>Lesezeichen der IDE: Nummer 0–9, Zeile 0-basiert.</summary>
  TAtlasIdeBookmarkPos = record
    Number: Integer;
    Line: Integer;
    class function Create(ANumber, ALine: Integer): TAtlasIdeBookmarkPos; static;
  end;

  TAtlasQuickBookmarks = class
  public const
    cMaxNumber = 9;
    /// <summary>Zweite Teile der Faltungsakkorde nach Strg+Umschalt+K in der Standard-Tastaturbelegung.</summary>
    cFoldLetters = 'ACEGMNOPRTU';
    cMinColumnWidth = 10;
  public
    /// <summary>Steht in der Spalte: schnelles oder nummeriertes Lesezeichen.</summary>
    class function InColumn(const ABookmark: TAtlasBookmark): Boolean; static;
    /// <summary>Gefundene Marker der Spalte an ALine (0-basiert): kleinste Nummer vorn, unnummerierte dahinter in
    /// der Reihenfolge der Liste.</summary>
    class function ColumnMarks(const AList: TAtlasBookmarkList; const AFileName: string;
      ALine: Integer): TArray<TAtlasBookmark>; static;
    /// <summary>Datei hat Marker für die Spalte (auch nicht gefundene).</summary>
    class function HasColumnMarks(const AList: TAtlasBookmarkList; const AFileName: string): Boolean; static;
    /// <summary>Neues schnelles Lesezeichen an ALine von AText (Text der Datei); ANumber 0 = unnummeriert. Liefert
    /// die Kennung.</summary>
    class function AddQuick(var AList: TAtlasBookmarkList; const AFileName, AText: string; ALine, ANumber: Integer;
      ANowUtc: TDateTime): string; static;
    /// <summary>Nummer ANumber (1–9) an ALine: entfernt, wenn sie schon dort steht, sonst neu bzw. umgezogen.
    /// </summary>
    class function SetNumber(var AList: TAtlasBookmarkList; const AFileName, AText: string;
      ALine, ANumber: Integer; ANowUtc: TDateTime): TAtlasQuickChange; static;
    /// <summary>Nummer eines vorhandenen Lesezeichens (Fenster, Menü „Nummer vergeben“): Hat es sie schon, fällt
    /// sie weg; sonst wechselt sie von ihrem bisherigen Träger hierher.</summary>
    class function AssignNumber(var AList: TAtlasBookmarkList; const AId: string;
      ANumber: Integer): TAtlasQuickChange; static;
    /// <summary>Unnummeriertes schnelles Lesezeichen an ALine setzen bzw. entfernen.</summary>
    class function Toggle(var AList: TAtlasBookmarkList; const AFileName, AText: string; ALine: Integer;
      ANowUtc: TDateTime): TAtlasQuickChange; static;
    /// <summary>Kleinste freie Nummer 1–9; 0, wenn alle belegt sind.</summary>
    class function FreeNumber(const AList: TAtlasBookmarkList): Integer; static;
    /// <summary>Klick in die Spalte: Marker der Zeile entfernen bzw. ein Lesezeichen mit der kleinsten freien
    /// Nummer setzen (ohne, wenn alle belegt sind).</summary>
    class function Click(var AList: TAtlasBookmarkList; const AFileName, AText: string; ALine: Integer;
      ANowUtc: TDateTime): TAtlasQuickChange; static;
    /// <summary>Marker der Zeile entfernen: schnelle ganz, benannte verlieren ihre Nummer. Anzahl.</summary>
    class function RemoveAt(var AList: TAtlasBookmarkList; const AFileName: string; ALine: Integer): Integer; static;
    /// <summary>Alle Marker der Datei entfernen (auch nicht gefundene); benannte Lesezeichen bleiben. Anzahl.
    /// </summary>
    class function RemoveFile(var AList: TAtlasBookmarkList; const AFileName: string): Integer; static;
    /// <summary>Sprungziel für Strg+ANumber; AIndex ist der Index in AList (-1 ohne).</summary>
    class function Jump(const AList: TAtlasBookmarkList; ANumber: Integer; const ACurrentFile: string;
      AScope: TAtlasQuickScope; out AIndex: Integer): TAtlasQuickJump; static;
    /// <summary>Nächste (AForward) bzw. vorige Zeile mit einem gefundenen Lesezeichen in AFileName, reihum von
    /// ALine aus. False ohne Lesezeichen in der Datei.</summary>
    class function Step(const AList: TAtlasBookmarkList; const AFileName: string; ALine: Integer; AForward: Boolean;
      out ATarget: Integer): Boolean; static;
    /// <summary>IDE-Lesezeichen 1–9 von AFileName übernehmen (0 bleibt bei der IDE). Liefert die übernommenen
    /// Nummern der IDE, die dort zu entfernen sind.</summary>
    class function Import(var AList: TAtlasBookmarkList; const AFileName, AText: string;
      const AMarks: TArray<TAtlasIdeBookmarkPos>; ANowUtc: TDateTime): TArray<Integer>; static;
    /// <summary>Entscheidung nach Strg+Umschalt+K: AWaitMs Wartezeit (0 = Atlas belegt die Taste nicht),
    /// AElapsedMs seit dem ersten Teil, AKey die nächste Taste (virtueller Tastencode, 0 = noch keine).</summary>
    class function Chord(AWaitMs, AElapsedMs: Integer; AKey: Word): TAtlasChordAction; static;
    /// <summary>Breite der Spalte in Pixeln zur Zeilenhöhe: Platz für Band und Ziffer, mindestens cMinColumnWidth.
    /// </summary>
    class function ColumnWidth(ALineHeight: Integer): Integer; static;
    /// <summary>Editorzeile unter der Höhe AY, geschätzt aus einer gezeichneten Zeile (AKnownLine, Oberkante
    /// AKnownTop, Höhe ALineHeight); auch über und unter ihr. Ohne Höhe AKnownLine.</summary>
    class function RowGuess(AKnownLine, AKnownTop, ALineHeight, AY: Integer): Integer; static;
    /// <summary>Taste für Nummer ANumber aus der Grundtaste ABase (Taste für 1); 0 ohne Grundtaste.</summary>
    class function KeyFor(ABase: Word; ANumber: Integer): Word; static;
    /// <summary>Nummer 1–9, wenn AShortCut die Grundtaste ABase mit einer anderen Ziffer ist; sonst 0.</summary>
    class function NumberOfKey(AShortCut, ABase: Word): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Marks.Ids;

const
  cKeyMask = $00FF;
  cModifierMask = $FF00;
  // Umschalttasten selbst (VK_SHIFT, VK_CONTROL, VK_MENU, linke/rechte Varianten): Der Nutzer hält sie noch.
  cModifierKeys: array[0..8] of Word = ($10, $11, $12, $A0, $A1, $A2, $A3, $A4, $A5);

{ TAtlasIdeBookmarkPos }

class function TAtlasIdeBookmarkPos.Create(ANumber, ALine: Integer): TAtlasIdeBookmarkPos;
begin
  Result.Number := ANumber;
  Result.Line := ALine;
end;

{ TAtlasQuickBookmarks }

class function TAtlasQuickBookmarks.InColumn(const ABookmark: TAtlasBookmark): Boolean;
begin
  Result := (ABookmark.Kind = TAtlasBookmarkKind.Quick) or (ABookmark.Number > 0);
end;

class function TAtlasQuickBookmarks.ColumnMarks(const AList: TAtlasBookmarkList; const AFileName: string;
  ALine: Integer): TArray<TAtlasBookmark>;
var
  mMark: TAtlasBookmark;
  mNumbered, mPlain: TArray<TAtlasBookmark>;
begin
  mNumbered := nil;
  mPlain := nil;
  for mMark in AList.AtLine(AFileName, ALine) do
  begin
    if InColumn(mMark) then
    begin
      if mMark.Number > 0 then
      begin
        mNumbered := mNumbered + [mMark];
      end
      else
      begin
        mPlain := mPlain + [mMark];
      end;
    end;
  end;
  TArray.Sort<TAtlasBookmark>(mNumbered, TComparer<TAtlasBookmark>.Construct(
    function(const A, B: TAtlasBookmark): Integer
    begin
      Result := A.Number - B.Number;
    end));
  Result := mNumbered + mPlain;
end;

class function TAtlasQuickBookmarks.HasColumnMarks(const AList: TAtlasBookmarkList; const AFileName: string): Boolean;
var
  mMark: TAtlasBookmark;
begin
  Result := False;
  for mMark in AList.ForFile(AFileName) do
  begin
    if InColumn(mMark) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasQuickBookmarks.AddQuick(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine, ANumber: Integer; ANowUtc: TDateTime): string;
var
  mIndex: Integer;
begin
  Result := AList.Add(AFileName, AText, ALine, '', ANowUtc);
  mIndex := AList.IndexOf(Result);
  AList.Bookmarks[mIndex].Kind := TAtlasBookmarkKind.Quick;
  if (ANumber >= 1) and (ANumber <= cMaxNumber) then
  begin
    AList.Bookmarks[mIndex].Number := ANumber;
  end;
end;

/// <summary>Nummer von AList.Bookmarks[AIndex] wegnehmen: Ein schnelles Lesezeichen ohne Namen verschwindet ganz,
/// sonst bleibt es ohne Nummer.</summary>
procedure DropNumber(var AList: TAtlasBookmarkList; AIndex: Integer);
begin
  if (AList.Bookmarks[AIndex].Kind = TAtlasBookmarkKind.Quick) and AList.Bookmarks[AIndex].Unnamed then
  begin
    Delete(AList.Bookmarks, AIndex, 1);
  end
  else
  begin
    AList.Bookmarks[AIndex].Number := 0;
  end;
end;

class function TAtlasQuickBookmarks.SetNumber(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine, ANumber: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
var
  mIndex: Integer;
  mMark: TAtlasBookmark;
begin
  Result := TAtlasQuickChange.None;
  if (ANumber < 1) or (ANumber > cMaxNumber) or (ALine < 0) then
  begin
    Exit;
  end;
  mIndex := AList.IndexOfNumber(ANumber);
  if mIndex >= 0 then
  begin
    mMark := AList.Bookmarks[mIndex];
    DropNumber(AList, mIndex);
    // Stand schon in dieser Zeile: nur entfernen.
    if not mMark.Lost and (mMark.Line = ALine) and TAtlasMarkIds.SameFile(mMark.FileName, AFileName) then
    begin
      Exit(TAtlasQuickChange.Removed);
    end;
    Result := TAtlasQuickChange.Moved;
  end
  else
  begin
    Result := TAtlasQuickChange.Added;
  end;
  AddQuick(AList, AFileName, AText, ALine, ANumber, ANowUtc);
end;

class function TAtlasQuickBookmarks.AssignNumber(var AList: TAtlasBookmarkList; const AId: string;
  ANumber: Integer): TAtlasQuickChange;
var
  mIndex, mHolder: Integer;
begin
  Result := TAtlasQuickChange.None;
  mIndex := AList.IndexOf(AId);
  if (mIndex < 0) or (ANumber < 1) or (ANumber > cMaxNumber) then
  begin
    Exit;
  end;
  if AList.Bookmarks[mIndex].Number = ANumber then
  begin
    // Hat sie schon: Nummer weg, das Lesezeichen bleibt (auch ein schnelles, es wird unnummeriert).
    AList.Bookmarks[mIndex].Number := 0;
    Exit(TAtlasQuickChange.Removed);
  end;
  Result := TAtlasQuickChange.Added;
  mHolder := AList.IndexOfNumber(ANumber);
  if mHolder >= 0 then
  begin
    // Der bisherige Träger behält sich selbst, nur ohne Nummer.
    AList.Bookmarks[mHolder].Number := 0;
    Result := TAtlasQuickChange.Moved;
  end;
  AList.Bookmarks[mIndex].Number := ANumber;
end;

class function TAtlasQuickBookmarks.Toggle(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
var
  mMark: TAtlasBookmark;
begin
  Result := TAtlasQuickChange.None;
  if ALine < 0 then
  begin
    Exit;
  end;
  for mMark in AList.AtLine(AFileName, ALine) do
  begin
    if (mMark.Kind = TAtlasBookmarkKind.Quick) and (mMark.Number = 0) then
    begin
      AList.Remove(mMark.Id);
      Exit(TAtlasQuickChange.Removed);
    end;
  end;
  AddQuick(AList, AFileName, AText, ALine, 0, ANowUtc);
  Result := TAtlasQuickChange.Added;
end;

class function TAtlasQuickBookmarks.FreeNumber(const AList: TAtlasBookmarkList): Integer;
begin
  Result := 1;
  while (Result <= cMaxNumber) and (AList.IndexOfNumber(Result) >= 0) do
  begin
    Inc(Result);
  end;
  if Result > cMaxNumber then
  begin
    Result := 0;
  end;
end;

class function TAtlasQuickBookmarks.Click(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
begin
  Result := TAtlasQuickChange.None;
  if ALine < 0 then
  begin
    Exit;
  end;
  if RemoveAt(AList, AFileName, ALine) > 0 then
  begin
    Exit(TAtlasQuickChange.Removed);
  end;
  // Die kleinste freie Nummer 1–9 gleich mit; sind alle belegt, ohne Nummer.
  AddQuick(AList, AFileName, AText, ALine, FreeNumber(AList), ANowUtc);
  Result := TAtlasQuickChange.Added;
end;

class function TAtlasQuickBookmarks.RemoveAt(var AList: TAtlasBookmarkList; const AFileName: string;
  ALine: Integer): Integer;
var
  mMark: TAtlasBookmark;
  mIndex: Integer;
begin
  Result := 0;
  for mMark in ColumnMarks(AList, AFileName, ALine) do
  begin
    mIndex := AList.IndexOf(mMark.Id);
    if mIndex < 0 then
    begin
      Continue;
    end;
    if AList.Bookmarks[mIndex].Kind = TAtlasBookmarkKind.Quick then
    begin
      Delete(AList.Bookmarks, mIndex, 1);
    end
    else
    begin
      AList.Bookmarks[mIndex].Number := 0;
    end;
    Inc(Result);
  end;
end;

class function TAtlasQuickBookmarks.RemoveFile(var AList: TAtlasBookmarkList; const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := High(AList.Bookmarks) downto 0 do
  begin
    if TAtlasMarkIds.SameFile(AList.Bookmarks[mIndex].FileName, AFileName) and InColumn(AList.Bookmarks[mIndex]) then
    begin
      if AList.Bookmarks[mIndex].Kind = TAtlasBookmarkKind.Quick then
      begin
        Delete(AList.Bookmarks, mIndex, 1);
      end
      else
      begin
        AList.Bookmarks[mIndex].Number := 0;
      end;
      Inc(Result);
    end;
  end;
end;

class function TAtlasQuickBookmarks.Jump(const AList: TAtlasBookmarkList; ANumber: Integer;
  const ACurrentFile: string; AScope: TAtlasQuickScope; out AIndex: Integer): TAtlasQuickJump;
begin
  AIndex := AList.IndexOfNumber(ANumber);
  if AIndex < 0 then
  begin
    Exit(TAtlasQuickJump.NotAssigned);
  end;
  if (AScope = TAtlasQuickScope.CurrentFile) and
    not TAtlasMarkIds.SameFile(AList.Bookmarks[AIndex].FileName, ACurrentFile) then
  begin
    Exit(TAtlasQuickJump.OtherFile);
  end;
  Result := TAtlasQuickJump.Found;
end;

/// <summary>Nächste Zeile nach ALine (AForward) bzw. davor in den sortierten ALines; am Ende ringsum.</summary>
function NextLine(const ALines: TArray<Integer>; ALine: Integer; AForward: Boolean): Integer;
var
  mLine: Integer;
begin
  if AForward then
  begin
    for mLine in ALines do
    begin
      if mLine > ALine then
      begin
        Exit(mLine);
      end;
    end;
    Exit(ALines[0]);
  end;
  Result := ALines[High(ALines)];
  for mLine in ALines do
  begin
    if mLine < ALine then
    begin
      Result := mLine;
    end;
  end;
end;

/// <summary>Steht an ALine von AFileName schon ein Lesezeichen in der Spalte?</summary>
function MarkedInColumn(const AList: TAtlasBookmarkList; const AFileName: string; ALine: Integer): Boolean;
var
  mExisting: TAtlasBookmark;
begin
  Result := False;
  for mExisting in AList.AtLine(AFileName, ALine) do
  begin
    if TAtlasQuickBookmarks.InColumn(mExisting) then
    begin
      Result := True;
    end;
  end;
end;

function IsModifierKey(AKey: Word): Boolean;
var
  mModifier: Word;
begin
  Result := False;
  for mModifier in cModifierKeys do
  begin
    if AKey = mModifier then
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasQuickBookmarks.Step(const AList: TAtlasBookmarkList; const AFileName: string; ALine: Integer;
  AForward: Boolean; out ATarget: Integer): Boolean;
var
  mMark: TAtlasBookmark;
  mLines: TArray<Integer>;
begin
  ATarget := -1;
  mLines := nil;
  for mMark in AList.ForFile(AFileName) do
  begin
    if not mMark.Lost then
    begin
      mLines := mLines + [mMark.Line];
    end;
  end;
  Result := Length(mLines) > 0;
  if Result then
  begin
    TArray.Sort<Integer>(mLines);
    ATarget := NextLine(mLines, ALine, AForward);
  end;
end;

class function TAtlasQuickBookmarks.Import(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  const AMarks: TArray<TAtlasIdeBookmarkPos>; ANowUtc: TDateTime): TArray<Integer>;
var
  mMark: TAtlasIdeBookmarkPos;
  mNumber: Integer;
begin
  Result := nil;
  for mMark in AMarks do
  begin
    // Lesezeichen 0 bleibt bei der IDE (Strg+0 und Strg+Umschalt+0 gehören ihr).
    if (mMark.Number < 1) or (mMark.Number > cMaxNumber) or (mMark.Line < 0) then
    begin
      Continue;
    end;
    mNumber := mMark.Number;
    // Nummer bei Atlas schon vergeben: unnummeriert übernehmen, nichts geht verloren.
    if AList.IndexOfNumber(mNumber) >= 0 then
    begin
      mNumber := 0;
    end;
    if (mNumber <> 0) or not MarkedInColumn(AList, AFileName, mMark.Line) then
    begin
      AddQuick(AList, AFileName, AText, mMark.Line, mNumber, ANowUtc);
    end;
    Result := Result + [mMark.Number];
  end;
end;

class function TAtlasQuickBookmarks.Chord(AWaitMs, AElapsedMs: Integer; AKey: Word): TAtlasChordAction;
var
  mLate: Boolean;
begin
  if AWaitMs <= 0 then
  begin
    Exit(TAtlasChordAction.Toggle);
  end;
  mLate := AElapsedMs >= AWaitMs;
  if (AKey = 0) or IsModifierKey(AKey) then
  begin
    if mLate then
    begin
      Result := TAtlasChordAction.Toggle;
    end
    else
    begin
      Result := TAtlasChordAction.Wait;
    end;
  end
  else if not mLate and (AKey < $80) and (Pos(Char(AKey), cFoldLetters) > 0) then
  begin
    Result := TAtlasChordAction.PassOn;
  end
  else
  begin
    // Andere Taste oder zu spät: Lesezeichen, die Taste läuft danach normal weiter.
    Result := TAtlasChordAction.Toggle;
  end;
end;

class function TAtlasQuickBookmarks.ColumnWidth(ALineHeight: Integer): Integer;
begin
  Result := (ALineHeight * 4) div 5;
  if Result < cMinColumnWidth then
  begin
    Result := cMinColumnWidth;
  end;
end;

class function TAtlasQuickBookmarks.RowGuess(AKnownLine, AKnownTop, ALineHeight, AY: Integer): Integer;
var
  mOffset: Integer;
begin
  Result := AKnownLine;
  if ALineHeight <= 0 then
  begin
    Exit;
  end;
  // Abrunden auch oberhalb der bekannten Zeile (div rundet zur Null).
  mOffset := AY - AKnownTop;
  if mOffset >= 0 then
  begin
    Result := AKnownLine + mOffset div ALineHeight;
  end
  else
  begin
    Result := AKnownLine - (ALineHeight - 1 - mOffset) div ALineHeight;
  end;
end;

class function TAtlasQuickBookmarks.KeyFor(ABase: Word; ANumber: Integer): Word;
begin
  Result := 0;
  if (ABase = 0) or (ANumber < 1) or (ANumber > cMaxNumber) then
  begin
    Exit;
  end;
  Result := Word((ABase and cModifierMask) or (Ord('0') + ANumber));
end;

class function TAtlasQuickBookmarks.NumberOfKey(AShortCut, ABase: Word): Integer;
var
  mDigit: Integer;
begin
  Result := 0;
  if (ABase = 0) or ((AShortCut and cModifierMask) <> (ABase and cModifierMask)) then
  begin
    Exit;
  end;
  mDigit := Integer(AShortCut and cKeyMask) - Ord('0');
  if (mDigit >= 1) and (mDigit <= cMaxNumber) then
  begin
    Result := mDigit;
  end;
end;

end.
