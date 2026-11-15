unit Atlas.Core.Editor.InlayPlan;

// Entscheidungen der Inlay-Hints im Editor (#401), ohne VCL und Open Tools API. Atlas.IDE.InlayHints.Editor liest
// Editor, Einstellungen und Zeitgeber und zeichnet mit GDI; was gezeichnet wird, steht hier:
//   - TAtlasInlayPlan: welche Dateien Marken bekommen, wann neu geholt wird (Tipp-Pause, Wartezeit nach einem
//     Fehler, Code sichtbar), welche Zeilen sichtbar sind, die Marken einer Zeile aus dem Speicher und welche Arten
//     davon bleiben (Einstellungen, Ausblenden am Element #628), ob die Zeile im Editor der im Speicher entspricht,
//     Spalte hinter dem Zeilenende, Schriftgröße der Pillen.
//   - TAtlasInlayPillHits: gezeichnete klickbare Marken (Blockende #620, „braucht kein Self“ #686) und welche unter
//     einem Linksklick liegt.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  System.Types,
  Atlas.Core.InlayHints.Store;

type
  /// <summary>Gezeichnete Blockende-Beschriftung (#620) oder Marke „braucht kein Self“ (#686) mit Ziel des
  /// Klicks.</summary>
  TAtlasInlayPillHit = record
    /// <summary>Datei der Marke.</summary>
    FileName: string;
    /// <summary>Zeile der Marke (0-basiert).</summary>
    Line: Integer;
    /// <summary>Oberste Zeile des Editors beim Zeichnen; gescrollt gilt die Fläche nicht mehr.</summary>
    TopRow: Integer;
    /// <summary>Fläche im Editor.</summary>
    Rect: TRect;
    /// <summary>Ziel des Sprungs (0-basiert).</summary>
    TargetLine: Integer;
    TargetCharacter: Integer;
    /// <summary>Marke einer Methode ohne Self: nach dem Sprung die Code-Aktionen öffnen.</summary>
    Actions: Boolean;
  end;

  /// <summary>Art einer Marke; die IDE-Schicht ordnet ihr das gezeichnete Element für .atlas zu.</summary>
  TAtlasInlayKind = (
    /// <summary>Parameternamen (#401).</summary>
    Parameters,
    /// <summary>Abgeleitete Typen (#453).</summary>
    InferredTypes,
    /// <summary>Include-Symbole (#860).</summary>
    Defines,
    /// <summary>Zeichencodes.</summary>
    Chars,
    /// <summary>„braucht kein Self“ (#686).</summary>
    Method,
    /// <summary>Blockende-Beschriftung (#620).</summary>
    BlockEnd);

  /// <summary>Eine Pille je Art mit ihren Beschriftungen.</summary>
  TAtlasInlayPillRow = record
    Kind: TAtlasInlayKind;
    Labels: TArray<string>;
  end;

  /// <summary>Marken einer Zeile: Pillen und die Blockende-Beschriftung.</summary>
  TAtlasInlayLine = record
    /// <summary>Zeile (0-basiert).</summary>
    Line: Integer;
    /// <summary>Text der Zeile im Speicher.</summary>
    Stored: string;
    TabWidth: Integer;
    Rows: TArray<TAtlasInlayPillRow>;
    ShowEnd: Boolean;
    EndText: string;
    EndLabel: string;
    EndHint: TAtlasInlayHint;
    /// <summary>Stelle der Marke „braucht kein Self“ (Ende des Kopfs, 0-basiert).</summary>
    MethodCharacter: Integer;
  end;

  /// <summary>Eingeschaltete Arten.</summary>
  TAtlasInlayKinds = set of TAtlasInlayKind;

  /// <summary>Ist die Art AKind am Text AText (Codezeile bzw. Beschriftung) in .atlas ausgeblendet (#628)?</summary>
  TAtlasInlayHiddenFunc = reference to function(AKind: TAtlasInlayKind; const AText: string): Boolean;

  /// <summary>Texte der Marken in der Sprache der IDE.</summary>
  TAtlasInlayTexts = record
    /// <summary>„braucht kein Self“ (#686).</summary>
    MethodWithoutSelf: string;
    /// <summary>Vorlage „definiert %s“ für ein Include-Symbol (#860).</summary>
    DefineFormat: string;
  end;

  /// <summary>Was die Inlay-Hints holen und zeichnen.</summary>
  TAtlasInlayPlan = record
  public const
    /// <summary>So lange nach der letzten Änderung gilt der neue Text.</summary>
    cQuietMs = 300;
    /// <summary>Kleinste Schriftgröße der Pillen.</summary>
    cMinFontSize = 6;
  public
    /// <summary>Pascal-Datei (.pas, .dpr, .dpk, .inc)? Nur dort gibt es Marken.</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Jetzt holen: Ansicht da, Stand unverändert seit der Tipp-Pause (AQuietMs), Wartezeit nach einem
    /// Fehler vorbei und der Code zu sehen (nicht Designer oder Willkommensseite).</summary>
    class function FetchDue(AHasView, AChanged: Boolean; AQuietMs: UInt64; ARetryReached, ACodeInFront: Boolean):
      Boolean; static;
    /// <summary>Sichtbare Zeilen (0-basiert, ALast exklusiv wie im Speicher) zur obersten Zeile ATopRow
    /// (1-basiert) und ARows Zeilen.</summary>
    class procedure VisibleLines(ATopRow, ARows: Integer; out AFirst, ALast: Integer); static;
    /// <summary>Marken der Zeile ALine aus dem Speicher, ohne Einstellungen; False, wenn es keine gibt.</summary>
    class function StoredLine(AStore: TAtlasInlayHintStore; const AFileName: string; ALine: Integer;
      const ATexts: TAtlasInlayTexts; out AHints: TAtlasInlayLine): Boolean; static;
    /// <summary>Nur eingeschaltete Arten (AOn, Blockende mit AEndOn), die AHidden nicht ausblendet (#628; nil prüft
    /// nicht). True, wenn etwas bleibt.</summary>
    class function KeepShown(var AHints: TAtlasInlayLine; AOn: TAtlasInlayKinds; AEndOn: Boolean;
      const AHidden: TAtlasInlayHiddenFunc): Boolean; static;
    /// <summary>Entspricht die Zeile im Editor AEditorLine der im Speicher? Tabs aufgelöst, Leerzeichen am Ende egal.
    /// </summary>
    class function SameLine(const AEditorLine, AStored: string; ATabWidth: Integer): Boolean; static;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex ACharacter (0-basiert) in ALine; Tabs aufgelöst.</summary>
    class function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
    /// <summary>Spalte der ersten Marke: zwei Zeichen hinter dem letzten Zeichen der Zeile.</summary>
    class function TailColumn(const AStored: string; ATabWidth: Integer): Integer; static;
    /// <summary>Schrift der Pillen: einen Punkt kleiner als die Editorschrift, mindestens 6.</summary>
    class function FontSize(AEditorSize: Integer): Integer; static;
    /// <summary>Zählt der Mausklick: links ohne Umschalt, Strg und Alt.</summary>
    class function CountsAsClick(ALeft: Boolean; AShift: TShiftState): Boolean; static;
    /// <summary>Gilt die gemerkte Fläche AHit noch? Blockende mit AEndOn; „braucht kein Self“ mit AMethodOn und nur,
    /// wenn der Speicher die Marke noch an derselben Stelle hat (AMethodStored, AMethodCharacter).</summary>
    class function HitStillShown(const AHit: TAtlasInlayPillHit; AEndOn, AMethodOn, AMethodStored: Boolean;
      AMethodCharacter: Integer): Boolean; static;
  end;

  /// <summary>Gilt die gemerkte Fläche noch (Art an, Marke noch da)?</summary>
  TAtlasInlayHitShownFunc = reference to function(const AHit: TAtlasInlayPillHit): Boolean;

  /// <summary>Gezeichnete klickbare Marken.</summary>
  TAtlasInlayPillHits = record
  public const
    /// <summary>Mehr gemerkte Flächen: alle vergessen (der Editor zeichnet sie ohnehin neu).</summary>
    cMaxHits = 500;
  private
    FHits: TArray<TAtlasInlayPillHit>;
  public
    /// <summary>Fläche merken; eine ältere derselben Art in derselben Zeile ersetzt sie.</summary>
    procedure Remember(const AHit: TAtlasInlayPillHit);
    procedure Clear;
    function Count: Integer;
    /// <summary>Gemerkte Fläche unter APoint in AFileName bei oberster Zeile ATopRow, die AShown noch gelten lässt.
    /// </summary>
    function Find(const AFileName: string; ATopRow: Integer; const APoint: TPoint;
      const AShown: TAtlasInlayHitShownFunc; out AHit: TAtlasInlayPillHit): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Editor.Pairs;

procedure AddRow(var AHints: TAtlasInlayLine; AKind: TAtlasInlayKind; const ALabels: TArray<string>);
var
  mRow: TAtlasInlayPillRow;
begin
  if Length(ALabels) = 0 then
  begin
    Exit;
  end;
  mRow.Kind := AKind;
  mRow.Labels := ALabels;
  AHints.Rows := AHints.Rows + [mRow];
end;

/// <summary>Include-Symbole (#860): „definiert COMPLIB_VCL“.</summary>
function DefineLabels(const ADefines: TArray<string>; const AFormat: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ADefines));
  for mIndex := 0 to High(ADefines) do
  begin
    Result[mIndex] := Format(AFormat, [ADefines[mIndex]]);
  end;
end;

{ TAtlasInlayPlan }

class function TAtlasInlayPlan.IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc');
end;

class function TAtlasInlayPlan.FetchDue(AHasView, AChanged: Boolean; AQuietMs: UInt64; ARetryReached,
  ACodeInFront: Boolean): Boolean;
begin
  // Bis zur Tipp-Pause bleiben die Marken unveränderter Zeilen stehen.
  Result := AHasView and not AChanged and (AQuietMs >= cQuietMs) and ARetryReached and ACodeInFront;
end;

class procedure TAtlasInlayPlan.VisibleLines(ATopRow, ARows: Integer; out AFirst, ALast: Integer);
begin
  AFirst := ATopRow - 1;
  ALast := AFirst + ARows;
end;

class function TAtlasInlayPlan.StoredLine(AStore: TAtlasInlayHintStore; const AFileName: string; ALine: Integer;
  const ATexts: TAtlasInlayTexts; out AHints: TAtlasInlayLine): Boolean;
begin
  AHints := Default(TAtlasInlayLine);
  AHints.Line := ALine;
  AddRow(AHints, TAtlasInlayKind.Parameters, AStore.OnLine(AFileName, ALine));
  // Typmarken (#453): „: TStringList“ in derselben Pille.
  AddRow(AHints, TAtlasInlayKind.InferredTypes, AStore.TypesOnLine(AFileName, ALine));
  AddRow(AHints, TAtlasInlayKind.Defines, DefineLabels(AStore.DefinesOnLine(AFileName, ALine),
    ATexts.DefineFormat));
  // Steuerzeichen (#862): „#3“ hinter ^C.
  AddRow(AHints, TAtlasInlayKind.Chars, AStore.CharsOnLine(AFileName, ALine));
  // Methode ohne Self (#686): „braucht kein Self“ hinter dem Kopf.
  if AStore.MethodOnLine(AFileName, ALine, AHints.MethodCharacter) then
  begin
    AddRow(AHints, TAtlasInlayKind.Method, TArray<string>.Create(ATexts.MethodWithoutSelf));
  end;
  AHints.ShowEnd := AStore.EndLabelOn(AFileName, ALine, AHints.EndText, AHints.EndLabel, AHints.EndHint);
  Result := (Length(AHints.Rows) > 0) or AHints.ShowEnd;
end;

class function TAtlasInlayPlan.KeepShown(var AHints: TAtlasInlayLine; AOn: TAtlasInlayKinds; AEndOn: Boolean;
  const AHidden: TAtlasInlayHiddenFunc): Boolean;
var
  mKept: TArray<TAtlasInlayPillRow>;
  mRow: TAtlasInlayPillRow;
begin
  mKept := nil;
  for mRow in AHints.Rows do
  begin
    // Inlay-Hints blendet .atlas je Codezeile aus, Beschriftungen je Text.
    if (mRow.Kind in AOn) and not (Assigned(AHidden) and AHidden(mRow.Kind, AHints.Stored)) then
    begin
      mKept := mKept + [mRow];
    end;
  end;
  AHints.Rows := mKept;
  AHints.ShowEnd := AHints.ShowEnd and AEndOn and
    not (Assigned(AHidden) and AHidden(TAtlasInlayKind.BlockEnd, AHints.EndText));
  Result := (Length(AHints.Rows) > 0) or AHints.ShowEnd;
end;

class function TAtlasInlayPlan.SameLine(const AEditorLine, AStored: string; ATabWidth: Integer): Boolean;
begin
  Result := TrimRight(TAtlasPairs.DisplayLine(AEditorLine, ATabWidth)) =
    TrimRight(TAtlasPairs.DisplayLine(AStored, ATabWidth));
end;

class function TAtlasInlayPlan.ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

class function TAtlasInlayPlan.TailColumn(const AStored: string; ATabWidth: Integer): Integer;
begin
  Result := ColumnOf(AStored, Length(TrimRight(AStored)), ATabWidth) + 2;
end;

class function TAtlasInlayPlan.FontSize(AEditorSize: Integer): Integer;
begin
  Result := Max(cMinFontSize, AEditorSize - 1);
end;

class function TAtlasInlayPlan.CountsAsClick(ALeft: Boolean; AShift: TShiftState): Boolean;
begin
  Result := ALeft and (AShift * [ssShift, ssCtrl, ssAlt] = []);
end;

class function TAtlasInlayPlan.HitStillShown(const AHit: TAtlasInlayPillHit; AEndOn, AMethodOn,
  AMethodStored: Boolean; AMethodCharacter: Integer): Boolean;
begin
  if not AHit.Actions then
  begin
    Exit(AEndOn);
  end;
  // Nach einer Änderung bleibt die alte Fläche gemerkt, bis die Zeile neu gezeichnet wird.
  Result := AMethodOn and AMethodStored and (AMethodCharacter = AHit.TargetCharacter);
end;

{ TAtlasInlayPillHits }

procedure TAtlasInlayPillHits.Remember(const AHit: TAtlasInlayPillHit);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHits) do
  begin
    if (FHits[mIndex].Line = AHit.Line) and (FHits[mIndex].Actions = AHit.Actions) and
      SameText(FHits[mIndex].FileName, AHit.FileName) then
    begin
      FHits[mIndex] := AHit;
      Exit;
    end;
  end;
  if Length(FHits) >= cMaxHits then
  begin
    FHits := nil;
  end;
  FHits := FHits + [AHit];
end;

procedure TAtlasInlayPillHits.Clear;
begin
  FHits := nil;
end;

function TAtlasInlayPillHits.Count: Integer;
begin
  Result := Length(FHits);
end;

function TAtlasInlayPillHits.Find(const AFileName: string; ATopRow: Integer; const APoint: TPoint;
  const AShown: TAtlasInlayHitShownFunc; out AHit: TAtlasInlayPillHit): Boolean;
var
  mHit: TAtlasInlayPillHit;
begin
  for mHit in FHits do
  begin
    // Nur, wenn die Marke noch dort steht (gleiche Datei, nicht gescrollt) und ihre Art noch an ist.
    if SameText(mHit.FileName, AFileName) and (mHit.TopRow = ATopRow) and mHit.Rect.Contains(APoint) and
      AShown(mHit) then
    begin
      AHit := mHit;
      Exit(True);
    end;
  end;
  AHit := Default(TAtlasInlayPillHit);
  Result := False;
end;

end.
