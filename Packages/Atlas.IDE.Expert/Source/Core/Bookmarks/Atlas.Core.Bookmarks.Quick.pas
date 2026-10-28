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
    MaxNumber = 9;
    /// <summary>Zweite Teile der Faltungsakkorde nach Strg+Umschalt+K in der Standard-Tastaturbelegung.</summary>
    FoldLetters = 'ACEGMNOPRTU';
    /// <summary>Vorgabe von bookmarks.quick.chordWait in ms.</summary>
    DefaultChordWait = 800;
    MinColumnWidth = 10;
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
    /// <summary>Breite der Spalte in Pixeln zur Zeilenhöhe: Platz für Band und Ziffer, mindestens MinColumnWidth.
    /// </summary>
    class function ColumnWidth(ALineHeight: Integer): Integer; static;
    /// <summary>Taste für Nummer ANumber aus der Grundtaste ABase (Taste für 1); 0 ohne Grundtaste.</summary>
    class function KeyFor(ABase: Word; ANumber: Integer): Word; static;
    /// <summary>Nummer 1–9, wenn AShortCut die Grundtaste ABase mit einer anderen Ziffer ist; sonst 0.</summary>
    class function NumberOfKey(AShortCut, ABase: Word): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

const
  KeyMask = $00FF;
  ModifierMask = $FF00;
  // Umschalttasten selbst (VK_SHIFT, VK_CONTROL, VK_MENU, linke/rechte Varianten): Der Nutzer hält sie noch.
  ModifierKeys: array[0..8] of Word = ($10, $11, $12, $A0, $A1, $A2, $A3, $A4, $A5);

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
  Mark: TAtlasBookmark;
  Numbered, Plain: TArray<TAtlasBookmark>;
begin
  Numbered := nil;
  Plain := nil;
  for Mark in AList.AtLine(AFileName, ALine) do
    if InColumn(Mark) then
    begin
      if Mark.Number > 0 then
        Numbered := Numbered + [Mark]
      else
        Plain := Plain + [Mark];
    end;
  TArray.Sort<TAtlasBookmark>(Numbered, TComparer<TAtlasBookmark>.Construct(
    function(const A, B: TAtlasBookmark): Integer
    begin
      Result := A.Number - B.Number;
    end));
  Result := Numbered + Plain;
end;

class function TAtlasQuickBookmarks.HasColumnMarks(const AList: TAtlasBookmarkList; const AFileName: string): Boolean;
var
  Mark: TAtlasBookmark;
begin
  Result := False;
  for Mark in AList.ForFile(AFileName) do
    if InColumn(Mark) then
      Exit(True);
end;

class function TAtlasQuickBookmarks.AddQuick(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine, ANumber: Integer; ANowUtc: TDateTime): string;
var
  Index: Integer;
begin
  Result := AList.Add(AFileName, AText, ALine, '', ANowUtc);
  Index := AList.IndexOf(Result);
  AList.Bookmarks[Index].Kind := TAtlasBookmarkKind.Quick;
  if (ANumber >= 1) and (ANumber <= MaxNumber) then
    AList.Bookmarks[Index].Number := ANumber;
end;

/// <summary>Nummer von AList.Bookmarks[AIndex] wegnehmen: Ein schnelles Lesezeichen ohne Namen verschwindet ganz,
/// sonst bleibt es ohne Nummer.</summary>
procedure DropNumber(var AList: TAtlasBookmarkList; AIndex: Integer);
begin
  if (AList.Bookmarks[AIndex].Kind = TAtlasBookmarkKind.Quick) and AList.Bookmarks[AIndex].Unnamed then
    Delete(AList.Bookmarks, AIndex, 1)
  else
    AList.Bookmarks[AIndex].Number := 0;
end;

class function TAtlasQuickBookmarks.SetNumber(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine, ANumber: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
var
  Index: Integer;
  Mark: TAtlasBookmark;
begin
  Result := TAtlasQuickChange.None;
  if (ANumber < 1) or (ANumber > MaxNumber) or (ALine < 0) then
    Exit;
  Index := AList.IndexOfNumber(ANumber);
  if Index >= 0 then
  begin
    Mark := AList.Bookmarks[Index];
    DropNumber(AList, Index);
    // Stand schon in dieser Zeile: nur entfernen.
    if not Mark.Lost and (Mark.Line = ALine) and TAtlasBookmarks.SameFile(Mark.FileName, AFileName) then
      Exit(TAtlasQuickChange.Removed);
    Result := TAtlasQuickChange.Moved;
  end
  else
    Result := TAtlasQuickChange.Added;
  AddQuick(AList, AFileName, AText, ALine, ANumber, ANowUtc);
end;

class function TAtlasQuickBookmarks.AssignNumber(var AList: TAtlasBookmarkList; const AId: string;
  ANumber: Integer): TAtlasQuickChange;
var
  Index, Holder: Integer;
begin
  Result := TAtlasQuickChange.None;
  Index := AList.IndexOf(AId);
  if (Index < 0) or (ANumber < 1) or (ANumber > MaxNumber) then
    Exit;
  if AList.Bookmarks[Index].Number = ANumber then
  begin
    // Hat sie schon: Nummer weg, das Lesezeichen bleibt (auch ein schnelles, es wird unnummeriert).
    AList.Bookmarks[Index].Number := 0;
    Exit(TAtlasQuickChange.Removed);
  end;
  Result := TAtlasQuickChange.Added;
  Holder := AList.IndexOfNumber(ANumber);
  if Holder >= 0 then
  begin
    // Der bisherige Träger behält sich selbst, nur ohne Nummer.
    AList.Bookmarks[Holder].Number := 0;
    Result := TAtlasQuickChange.Moved;
  end;
  AList.Bookmarks[Index].Number := ANumber;
end;

class function TAtlasQuickBookmarks.Toggle(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
var
  Mark: TAtlasBookmark;
begin
  Result := TAtlasQuickChange.None;
  if ALine < 0 then
    Exit;
  for Mark in AList.AtLine(AFileName, ALine) do
    if (Mark.Kind = TAtlasBookmarkKind.Quick) and (Mark.Number = 0) then
    begin
      AList.Remove(Mark.Id);
      Exit(TAtlasQuickChange.Removed);
    end;
  AddQuick(AList, AFileName, AText, ALine, 0, ANowUtc);
  Result := TAtlasQuickChange.Added;
end;

class function TAtlasQuickBookmarks.FreeNumber(const AList: TAtlasBookmarkList): Integer;
begin
  Result := 1;
  while (Result <= MaxNumber) and (AList.IndexOfNumber(Result) >= 0) do
    Inc(Result);
  if Result > MaxNumber then
    Result := 0;
end;

class function TAtlasQuickBookmarks.Click(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  ALine: Integer; ANowUtc: TDateTime): TAtlasQuickChange;
begin
  Result := TAtlasQuickChange.None;
  if ALine < 0 then
    Exit;
  if RemoveAt(AList, AFileName, ALine) > 0 then
    Exit(TAtlasQuickChange.Removed);
  // Die kleinste freie Nummer 1–9 gleich mit (Marco 28.10.2026); sind alle belegt, ohne Nummer.
  AddQuick(AList, AFileName, AText, ALine, FreeNumber(AList), ANowUtc);
  Result := TAtlasQuickChange.Added;
end;

class function TAtlasQuickBookmarks.RemoveAt(var AList: TAtlasBookmarkList; const AFileName: string;
  ALine: Integer): Integer;
var
  Mark: TAtlasBookmark;
  Index: Integer;
begin
  Result := 0;
  for Mark in ColumnMarks(AList, AFileName, ALine) do
  begin
    Index := AList.IndexOf(Mark.Id);
    if Index < 0 then
      Continue;
    if AList.Bookmarks[Index].Kind = TAtlasBookmarkKind.Quick then
      Delete(AList.Bookmarks, Index, 1)
    else
      AList.Bookmarks[Index].Number := 0;
    Inc(Result);
  end;
end;

class function TAtlasQuickBookmarks.RemoveFile(var AList: TAtlasBookmarkList; const AFileName: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := High(AList.Bookmarks) downto 0 do
    if TAtlasBookmarks.SameFile(AList.Bookmarks[Index].FileName, AFileName) and InColumn(AList.Bookmarks[Index]) then
    begin
      if AList.Bookmarks[Index].Kind = TAtlasBookmarkKind.Quick then
        Delete(AList.Bookmarks, Index, 1)
      else
        AList.Bookmarks[Index].Number := 0;
      Inc(Result);
    end;
end;

class function TAtlasQuickBookmarks.Jump(const AList: TAtlasBookmarkList; ANumber: Integer;
  const ACurrentFile: string; AScope: TAtlasQuickScope; out AIndex: Integer): TAtlasQuickJump;
begin
  AIndex := AList.IndexOfNumber(ANumber);
  if AIndex < 0 then
    Exit(TAtlasQuickJump.NotAssigned);
  if (AScope = TAtlasQuickScope.CurrentFile) and
    not TAtlasBookmarks.SameFile(AList.Bookmarks[AIndex].FileName, ACurrentFile) then
    Exit(TAtlasQuickJump.OtherFile);
  Result := TAtlasQuickJump.Found;
end;

class function TAtlasQuickBookmarks.Step(const AList: TAtlasBookmarkList; const AFileName: string; ALine: Integer;
  AForward: Boolean; out ATarget: Integer): Boolean;
var
  Mark: TAtlasBookmark;
  Lines: TArray<Integer>;
  Line: Integer;
begin
  ATarget := -1;
  Lines := nil;
  for Mark in AList.ForFile(AFileName) do
    if not Mark.Lost then
      Lines := Lines + [Mark.Line];
  Result := Length(Lines) > 0;
  if not Result then
    Exit;
  TArray.Sort<Integer>(Lines);
  if AForward then
  begin
    for Line in Lines do
      if Line > ALine then
      begin
        ATarget := Line;
        Exit;
      end;
    ATarget := Lines[0];
  end
  else
  begin
    ATarget := Lines[High(Lines)];
    for Line in Lines do
      if Line < ALine then
        ATarget := Line;
  end;
end;

class function TAtlasQuickBookmarks.Import(var AList: TAtlasBookmarkList; const AFileName, AText: string;
  const AMarks: TArray<TAtlasIdeBookmarkPos>; ANowUtc: TDateTime): TArray<Integer>;
var
  Mark: TAtlasIdeBookmarkPos;
  Existing: TAtlasBookmark;
  Number: Integer;
  Present: Boolean;
begin
  Result := nil;
  for Mark in AMarks do
  begin
    // Lesezeichen 0 bleibt bei der IDE (Strg+0 und Strg+Umschalt+0 gehören ihr).
    if (Mark.Number < 1) or (Mark.Number > MaxNumber) or (Mark.Line < 0) then
      Continue;
    Number := Mark.Number;
    // Nummer bei Atlas schon vergeben: unnummeriert übernehmen, nichts geht verloren.
    if AList.IndexOfNumber(Number) >= 0 then
      Number := 0;
    Present := False;
    if Number = 0 then
      for Existing in AList.AtLine(AFileName, Mark.Line) do
        if InColumn(Existing) then
          Present := True;
    if not Present then
      AddQuick(AList, AFileName, AText, Mark.Line, Number, ANowUtc);
    Result := Result + [Mark.Number];
  end;
end;

class function TAtlasQuickBookmarks.Chord(AWaitMs, AElapsedMs: Integer; AKey: Word): TAtlasChordAction;
var
  Modifier: Word;
begin
  if AWaitMs <= 0 then
    Exit(TAtlasChordAction.Toggle);
  if AKey <> 0 then
  begin
    for Modifier in ModifierKeys do
      if AKey = Modifier then
      begin
        if AElapsedMs >= AWaitMs then
          Exit(TAtlasChordAction.Toggle);
        Exit(TAtlasChordAction.Wait);
      end;
    if (AElapsedMs < AWaitMs) and (AKey < $80) and (Pos(Char(AKey), FoldLetters) > 0) then
      Exit(TAtlasChordAction.PassOn);
    // Andere Taste oder zu spät: Lesezeichen, die Taste läuft danach normal weiter.
    Exit(TAtlasChordAction.Toggle);
  end;
  if AElapsedMs >= AWaitMs then
    Result := TAtlasChordAction.Toggle
  else
    Result := TAtlasChordAction.Wait;
end;

class function TAtlasQuickBookmarks.ColumnWidth(ALineHeight: Integer): Integer;
begin
  Result := (ALineHeight * 4) div 5;
  if Result < MinColumnWidth then
    Result := MinColumnWidth;
end;

class function TAtlasQuickBookmarks.KeyFor(ABase: Word; ANumber: Integer): Word;
begin
  Result := 0;
  if (ABase = 0) or (ANumber < 1) or (ANumber > MaxNumber) then
    Exit;
  Result := Word((ABase and ModifierMask) or (Ord('0') + ANumber));
end;

class function TAtlasQuickBookmarks.NumberOfKey(AShortCut, ABase: Word): Integer;
var
  Digit: Integer;
begin
  Result := 0;
  if (ABase = 0) or ((AShortCut and ModifierMask) <> (ABase and ModifierMask)) then
    Exit;
  Digit := Integer(AShortCut and KeyMask) - Ord('0');
  if (Digit >= 1) and (Digit <= MaxNumber) then
    Result := Digit;
end;

end.
