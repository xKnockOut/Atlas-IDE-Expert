unit Atlas.Core.Editor.Hide;

// „Ausblenden“ direkt am Element (#628), Kernlogik ohne VCL und Open Tools
// API. Plan bestimmt, was ein Bereich an einem Element bewirkt:
// - Befund mit Regel (Atlas-Server): „Nur hier“ = Zeilenkommentar
//   "// lsp-ignore: regel" in einer eigenen Zeile über dem Befund (steht dort
//   schon ein solcher Kommentar, kommt die Regel dazu, vor einer Begründung
//   "-- …"); „In dieser Datei“ = "// lsp-ignore-file: regel" in der ersten
//   Zeile (bzw. ergänzt einen vorhandenen). Syntax wie #147
//   (Atlas.Common.Rules.Suppressions).
// - Andere Elemente und Befunde ohne Regel (Compiler): Eintrag "hidden" in der
//   Projektdatei .atlas (#486), mit Anker bzw. ohne für die ganze Datei.
// - „Überall“: die Einstellung des Elements aus (Wahrheitswert False, eine
//   Textauswahl wie welcomePage.whatsNew "off").
// Rückgängig: Einfügung wieder entfernen, sofern der Text dort noch steht;
// Eintrag aus .atlas entfernen; alten Wert der Einstellung zurück.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.HiddenPlaces;

type
  /// <summary>Das Element, an dem ausgeblendet wird.</summary>
  TAtlasHideTarget = record
    Element: TAtlasDrawnElement;
    /// <summary>Vollständiger Pfad der Datei im Editor.</summary>
    FileName: string;
    /// <summary>Zeile des Elements, 0-basiert (bei Befunden die erste Zeile).</summary>
    Line: Integer;
    /// <summary>Anker für .atlas (TAtlasDrawnElements.Anchor).</summary>
    Anchor: string;
    /// <summary>Nur Befunde: Regel des Servers; '' bei Compiler- und Syntaxfehlern.</summary>
    RuleId: string;
    /// <summary>Kurzer Text zum Element für das Menü (Beschriftung, Meldung); darf leer sein.</summary>
    Caption: string;
    class function Create(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
      const AAnchor: string): TAtlasHideTarget; static;
    /// <summary>Befund mit Regel ARuleId ('' = ohne Regel); Anker ist die Codezeile.</summary>
    class function Finding(const AFileName: string; ALine: Integer; const ARuleId, ALineText: string): TAtlasHideTarget;
      static;
    /// <summary>Bietet das Element den Bereich an?</summary>
    function Offers(AScope: TAtlasHideScope): Boolean;
    function SettingKey: string;
  end;

  /// <summary>Einfügung in den Text der Datei; Text '' = nichts zu tun.</summary>
  TAtlasTextInsert = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert, UTF-16-Einheiten.</summary>
    Character: Integer;
    Text: string;
    function IsEmpty: Boolean;
    function ApplyTo(const AText: string): string;
    /// <summary>Offset (0-basiert) der Einfügestelle in AText.</summary>
    function OffsetIn(const AText: string): Integer;
    /// <summary>Nimmt die Einfügung aus AText zurück; False, wenn der Text dort nicht mehr steht.</summary>
    function RevertIn(const AText: string; out AResult: string): Boolean;
  end;

{$SCOPEDENUMS ON}
  TAtlasHideKind = (
    /// <summary>Zeilenkommentar lsp-ignore.</summary>
    LineComment,
    /// <summary>Dateikommentar lsp-ignore-file.</summary>
    FileComment,
    /// <summary>Eintrag "hidden" in .atlas.</summary>
    TeamFile,
    /// <summary>Einstellung aus.</summary>
    Setting);
{$SCOPEDENUMS OFF}

  TAtlasHidePlan = record
    Target: TAtlasHideTarget;
    Scope: TAtlasHideScope;
    Kind: TAtlasHideKind;
    /// <summary>LineComment, FileComment.</summary>
    Insert: TAtlasTextInsert;
    /// <summary>TeamFile.</summary>
    Place: TAtlasHiddenPlace;
    /// <summary>Schlüssel der Einstellung des Elements (bei Setting die geänderte).</summary>
    SettingKey: string;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Warum kein Plan möglich ist.</summary>
  TAtlasHideRefusal = (None, ScopeNotOffered, NoProjectFolder, OutsideProject, AlreadyHidden);
{$SCOPEDENUMS OFF}

  TAtlasHide = class
  public const
    LineMarker = '// lsp-ignore: ';
    FileMarker = '// lsp-ignore-file: ';
  public
    /// <summary>Plan für ATarget im Bereich AScope. AText: aktueller Text der Datei (für Kommentare);
    /// ATeamFolder: Ordner der .atlas des Projekts ('' = keiner bekannt).</summary>
    class function Plan(const ATarget: TAtlasHideTarget; AScope: TAtlasHideScope; const AText, ATeamFolder: string;
      out APlan: TAtlasHidePlan; out ARefusal: TAtlasHideRefusal): Boolean; static;
    /// <summary>Unterdrückt ARuleId in ALine (0-basiert); leere Einfügung, wenn schon unterdrückt.</summary>
    class function SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TAtlasTextInsert; static;
    /// <summary>Unterdrückt ARuleId in der ganzen Datei; leere Einfügung, wenn schon unterdrückt.</summary>
    class function SuppressFile(const AText, ARuleId: string): TAtlasTextInsert; static;
    /// <summary>Setzt AKey aus (False bzw. "off"); AOldValue ist der alte Wert als Text. False, wenn es den
    /// Schlüssel nicht gibt oder er schon aus ist.</summary>
    class function SwitchOff(var ASettings: TAtlasPluginSettings; const AKey: string;
      out AOldValue: string): Boolean; static;
    /// <summary>Setzt AKey wieder auf AOldValue (Text aus SwitchOff); False ohne Schlüssel.</summary>
    class function Restore(var ASettings: TAtlasPluginSettings; const AKey, AOldValue: string): Boolean; static;
    /// <summary>Ist AKey eingeschaltet (Wahrheitswert True bzw. Text nicht "off")? False ohne Schlüssel.</summary>
    class function IsOn(const ASettings: TAtlasPluginSettings; const AKey: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Core.Settings.History;

/// <summary>Kennungen eines lsp-ignore-Kommentars ab AStart (1-basiert) bis vor "--"; AEnd ist die Stelle
/// (1-basiert) hinter der letzten Kennung.</summary>
function IdsOf(const ALine: string; AStart: Integer; out AEnd: Integer): TArray<string>;
var
  mIndex, mStop, mFrom: Integer;
begin
  Result := nil;
  mStop := Length(ALine) + 1;
  mIndex := AStart;
  while mIndex <= Length(ALine) do
  begin
    // Begründung nach "--" am Anfang einer Kennung (wie TSuppressions).
    if Copy(ALine, mIndex, 2) = '--' then
    begin
      mStop := mIndex;
      Break;
    end;
    if CharInSet(ALine[mIndex], [',', ' ', #9]) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mFrom := mIndex;
    while (mIndex <= Length(ALine)) and not CharInSet(ALine[mIndex], [',', ' ', #9]) do
    begin
      Inc(mIndex);
    end;
    Result := Result + [LowerCase(Copy(ALine, mFrom, mIndex - mFrom))];
  end;
  AEnd := mStop;
  while (AEnd > AStart) and CharInSet(ALine[AEnd - 1], [',', ' ', #9]) do
  begin
    Dec(AEnd);
  end;
end;

function Covers(const AIds: TArray<string>; const ARuleId: string): Boolean;
var
  mId: string;
begin
  for mId in AIds do
  begin
    if (mId = '*') or SameText(mId, ARuleId) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ergänzung eines vorhandenen Kommentars in ALine (Zeile ALineIndex) um ARuleId; False, wenn ALine
/// kein //-Kommentar mit AWord ("lsp-ignore:") allein in der Zeile ist.</summary>
function ExtendComment(const ALine: string; ALineIndex: Integer; const AWord, ARuleId: string;
  out AInsert: TAtlasTextInsert): Boolean;
var
  mStart, mStop: Integer;
  mIds: TArray<string>;
begin
  AInsert := Default(TAtlasTextInsert);
  // "//", Leerraum, Schlüsselwort; davor nur Einrückung.
  mStart := 1;
  while (mStart <= Length(ALine)) and CharInSet(ALine[mStart], [' ', #9]) do
  begin
    Inc(mStart);
  end;
  Result := Copy(ALine, mStart, 2) = '//';
  if not Result then
  begin
    Exit;
  end;
  Inc(mStart, 2);
  while (mStart <= Length(ALine)) and CharInSet(ALine[mStart], [' ', #9]) do
  begin
    Inc(mStart);
  end;
  Result := SameText(Copy(ALine, mStart, Length(AWord)), AWord);
  if not Result then
  begin
    Exit;
  end;
  Inc(mStart, Length(AWord));
  mIds := IdsOf(ALine, mStart, mStop);
  AInsert.Line := ALineIndex;
  AInsert.Character := mStop - 1;
  if Covers(mIds, ARuleId) then
  begin
    Exit;
  end;
  if Length(mIds) = 0 then
  begin
    AInsert.Text := ' ' + ARuleId;
  end
  else
  begin
    AInsert.Text := ', ' + ARuleId;
  end;
end;

{ TAtlasHideTarget }

class function TAtlasHideTarget.Create(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
  const AAnchor: string): TAtlasHideTarget;
begin
  Result := Default(TAtlasHideTarget);
  Result.Element := AElement;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Anchor := TAtlasDrawnElements.Anchor(AAnchor);
end;

class function TAtlasHideTarget.Finding(const AFileName: string; ALine: Integer;
  const ARuleId, ALineText: string): TAtlasHideTarget;
begin
  Result := Create(TAtlasDrawnElement.Problems, AFileName, ALine, ALineText);
  Result.RuleId := Trim(ARuleId);
end;

function TAtlasHideTarget.Offers(AScope: TAtlasHideScope): Boolean;
begin
  Result := AScope in TAtlasDrawnElements.Info(Element).Scopes;
end;

function TAtlasHideTarget.SettingKey: string;
begin
  Result := TAtlasDrawnElements.SettingKey(Element);
end;

{ TAtlasTextInsert }

function TAtlasTextInsert.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

function TAtlasTextInsert.OffsetIn(const AText: string): Integer;
begin
  Result := TLineTable.Build(AText).OffsetAt(TTextPosition.Create(Line, Character));
end;

function TAtlasTextInsert.ApplyTo(const AText: string): string;
var
  mOffset: Integer;
begin
  if IsEmpty then
  begin
    Exit(AText);
  end;
  mOffset := OffsetIn(AText);
  Result := Copy(AText, 1, mOffset) + Text + Copy(AText, mOffset + 1, MaxInt);
end;

function TAtlasTextInsert.RevertIn(const AText: string; out AResult: string): Boolean;
var
  mOffset: Integer;
begin
  AResult := AText;
  if IsEmpty then
  begin
    Exit(True);
  end;
  mOffset := OffsetIn(AText);
  Result := Copy(AText, mOffset + 1, Length(Text)) = Text;
  if Result then
  begin
    AResult := Copy(AText, 1, mOffset) + Copy(AText, mOffset + Length(Text) + 1, MaxInt);
  end;
end;

{ TAtlasHide }

class function TAtlasHide.SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TAtlasTextInsert;
var
  mLines: TArray<string>;
  mLine: string;
begin
  mLines := TTextLines.SplitLines(AText);
  // Steht darüber schon ein Kommentar allein in seiner Zeile, kommt die Regel dazu.
  if (ALine > 0) and (ALine - 1 <= High(mLines)) and
    ExtendComment(mLines[ALine - 1], ALine - 1, 'lsp-ignore:', ARuleId, Result) then
  begin
    Exit;
  end;
  mLine := '';
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    mLine := mLines[ALine];
  end;
  Result := Default(TAtlasTextInsert);
  Result.Line := ALine;
  Result.Character := 0;
  Result.Text := TTextLines.IndentOf(mLine) + LineMarker + ARuleId + TTextLines.LineBreakOf(AText);
end;

class function TAtlasHide.SuppressFile(const AText, ARuleId: string): TAtlasTextInsert;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  mLines := TTextLines.SplitLines(AText);
  for mIndex := 0 to High(mLines) do
  begin
    if ExtendComment(mLines[mIndex], mIndex, 'lsp-ignore-file:', ARuleId, Result) then
    begin
      Exit;
    end;
  end;
  Result := Default(TAtlasTextInsert);
  Result.Text := FileMarker + ARuleId + TTextLines.LineBreakOf(AText);
end;

/// <summary>Befund mit Regel: Unterdrückungskommentar (#147); False mit AlreadyHidden, wenn er schon steht.
/// </summary>
function CommentPlan(const ATarget: TAtlasHideTarget; AScope: TAtlasHideScope; const AText: string;
  var APlan: TAtlasHidePlan; out ARefusal: TAtlasHideRefusal): Boolean;
begin
  ARefusal := TAtlasHideRefusal.None;
  if AScope = TAtlasHideScope.Here then
  begin
    APlan.Kind := TAtlasHideKind.LineComment;
    APlan.Insert := TAtlasHide.SuppressLine(AText, ATarget.Line, ATarget.RuleId);
  end
  else
  begin
    APlan.Kind := TAtlasHideKind.FileComment;
    APlan.Insert := TAtlasHide.SuppressFile(AText, ATarget.RuleId);
  end;
  Result := not APlan.Insert.IsEmpty;
  if not Result then
  begin
    ARefusal := TAtlasHideRefusal.AlreadyHidden;
  end;
end;

/// <summary>Eintrag in der Projektdatei .atlas; False mit dem Grund, wenn keiner möglich ist.</summary>
function TeamFilePlan(const ATarget: TAtlasHideTarget; AScope: TAtlasHideScope; const ATeamFolder: string;
  var APlan: TAtlasHidePlan; out ARefusal: TAtlasHideRefusal): Boolean;
var
  mRelative, mAnchor: string;
begin
  ARefusal := TAtlasHideRefusal.None;
  mAnchor := '';
  if AScope = TAtlasHideScope.Here then
  begin
    mAnchor := ATarget.Anchor;
  end;
  if ATeamFolder = '' then
  begin
    ARefusal := TAtlasHideRefusal.NoProjectFolder;
  end
  else if not TAtlasHiddenPlaces.Relative(ATeamFolder, ATarget.FileName, mRelative) then
  begin
    ARefusal := TAtlasHideRefusal.OutsideProject;
  end
  else if (AScope = TAtlasHideScope.Here) and (mAnchor = '') then
  begin
    // Ohne Anker gäbe es keine einzelne Stelle: dann gilt der Eintrag nur mit Zeilennummer nicht.
    ARefusal := TAtlasHideRefusal.ScopeNotOffered;
  end
  else
  begin
    APlan.Kind := TAtlasHideKind.TeamFile;
    APlan.Place := TAtlasHiddenPlace.Create(ATarget.SettingKey, mRelative, mAnchor);
  end;
  Result := ARefusal = TAtlasHideRefusal.None;
end;

class function TAtlasHide.Plan(const ATarget: TAtlasHideTarget; AScope: TAtlasHideScope;
  const AText, ATeamFolder: string; out APlan: TAtlasHidePlan; out ARefusal: TAtlasHideRefusal): Boolean;
begin
  APlan := Default(TAtlasHidePlan);
  APlan.Target := ATarget;
  APlan.Scope := AScope;
  APlan.SettingKey := ATarget.SettingKey;
  ARefusal := TAtlasHideRefusal.None;
  if not ATarget.Offers(AScope) then
  begin
    ARefusal := TAtlasHideRefusal.ScopeNotOffered;
    Result := False;
  end
  else if AScope = TAtlasHideScope.Everywhere then
  begin
    APlan.Kind := TAtlasHideKind.Setting;
    Result := True;
  end
  else if (ATarget.Element = TAtlasDrawnElement.Problems) and (ATarget.RuleId <> '') then
  begin
    Result := CommentPlan(ATarget, AScope, AText, APlan, ARefusal);
  end
  else
  begin
    // Sonst Eintrag in der Projektdatei.
    Result := TeamFilePlan(ATarget, AScope, ATeamFolder, APlan, ARefusal);
  end;
end;

class function TAtlasHide.IsOn(const ASettings: TAtlasPluginSettings; const AKey: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if mStore.HasInteger(AKey) then
  begin
    Result := mStore.ReadInteger(AKey, 0) <> 0;
  end
  else
  begin
    Result := (mStore.Text(AKey) <> '') and not SameText(mStore.Text(AKey), 'off');
  end;
end;

class function TAtlasHide.SwitchOff(var ASettings: TAtlasPluginSettings; const AKey: string;
  out AOldValue: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  AOldValue := mStore.Text(AKey);
  Result := (AOldValue <> '') and IsOn(ASettings, AKey);
  if not Result then
  begin
    Exit;
  end;
  if mStore.HasInteger(AKey) then
  begin
    mStore.WriteInteger(AKey, 0);
  end
  else
  begin
    mStore.WriteString(AKey, 'off');
  end;
  ASettings.Load(mStore);
end;

class function TAtlasHide.Restore(var ASettings: TAtlasPluginSettings; const AKey, AOldValue: string): Boolean;
var
  mStore: IAtlasMemorySettingsStore;
begin
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := mStore.Text(AKey) <> '';
  if not Result then
  begin
    Exit;
  end;
  if mStore.HasInteger(AKey) then
  begin
    mStore.WriteInteger(AKey, StrToIntDef(AOldValue, 1));
  end
  else
  begin
    mStore.WriteString(AKey, AOldValue);
  end;
  ASettings.Load(mStore);
end;

end.
