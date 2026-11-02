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
  Index, Stop, From: Integer;
begin
  Result := nil;
  Stop := Length(ALine) + 1;
  Index := AStart;
  while Index <= Length(ALine) do
  begin
    // Begründung nach "--" am Anfang einer Kennung (wie TSuppressions).
    if Copy(ALine, Index, 2) = '--' then
    begin
      Stop := Index;
      Break;
    end;
    if CharInSet(ALine[Index], [',', ' ', #9]) then
    begin
      Inc(Index);
      Continue;
    end;
    From := Index;
    while (Index <= Length(ALine)) and not CharInSet(ALine[Index], [',', ' ', #9]) do
      Inc(Index);
    Result := Result + [LowerCase(Copy(ALine, From, Index - From))];
  end;
  AEnd := Stop;
  while (AEnd > AStart) and CharInSet(ALine[AEnd - 1], [',', ' ', #9]) do
    Dec(AEnd);
end;

function Covers(const AIds: TArray<string>; const ARuleId: string): Boolean;
var
  Id: string;
begin
  for Id in AIds do
    if (Id = '*') or SameText(Id, ARuleId) then
      Exit(True);
  Result := False;
end;

/// <summary>Ergänzung eines vorhandenen Kommentars in ALine (Zeile ALineIndex) um ARuleId; False, wenn ALine
/// kein //-Kommentar mit AWord ("lsp-ignore:") allein in der Zeile ist.</summary>
function ExtendComment(const ALine: string; ALineIndex: Integer; const AWord, ARuleId: string;
  out AInsert: TAtlasTextInsert): Boolean;
var
  Start, Stop: Integer;
  Ids: TArray<string>;
begin
  AInsert := Default(TAtlasTextInsert);
  // "//", Leerraum, Schlüsselwort; davor nur Einrückung.
  Start := 1;
  while (Start <= Length(ALine)) and CharInSet(ALine[Start], [' ', #9]) do
    Inc(Start);
  Result := Copy(ALine, Start, 2) = '//';
  if not Result then
    Exit;
  Inc(Start, 2);
  while (Start <= Length(ALine)) and CharInSet(ALine[Start], [' ', #9]) do
    Inc(Start);
  Result := SameText(Copy(ALine, Start, Length(AWord)), AWord);
  if not Result then
    Exit;
  Inc(Start, Length(AWord));
  Ids := IdsOf(ALine, Start, Stop);
  AInsert.Line := ALineIndex;
  AInsert.Character := Stop - 1;
  if Covers(Ids, ARuleId) then
    Exit;
  if Length(Ids) = 0 then
    AInsert.Text := ' ' + ARuleId
  else
    AInsert.Text := ', ' + ARuleId;
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
  Offset: Integer;
begin
  if IsEmpty then
    Exit(AText);
  Offset := OffsetIn(AText);
  Result := Copy(AText, 1, Offset) + Text + Copy(AText, Offset + 1, MaxInt);
end;

function TAtlasTextInsert.RevertIn(const AText: string; out AResult: string): Boolean;
var
  Offset: Integer;
begin
  AResult := AText;
  if IsEmpty then
    Exit(True);
  Offset := OffsetIn(AText);
  Result := Copy(AText, Offset + 1, Length(Text)) = Text;
  if Result then
    AResult := Copy(AText, 1, Offset) + Copy(AText, Offset + Length(Text) + 1, MaxInt);
end;

{ TAtlasHide }

class function TAtlasHide.SuppressLine(const AText: string; ALine: Integer; const ARuleId: string): TAtlasTextInsert;
var
  Lines: TArray<string>;
  Line: string;
begin
  Lines := TTextLines.SplitLines(AText);
  // Steht darüber schon ein Kommentar allein in seiner Zeile, kommt die Regel dazu.
  if (ALine > 0) and (ALine - 1 <= High(Lines)) and
    ExtendComment(Lines[ALine - 1], ALine - 1, 'lsp-ignore:', ARuleId, Result) then
    Exit;
  Line := '';
  if (ALine >= 0) and (ALine <= High(Lines)) then
    Line := Lines[ALine];
  Result := Default(TAtlasTextInsert);
  Result.Line := ALine;
  Result.Character := 0;
  Result.Text := TTextLines.IndentOf(Line) + LineMarker + ARuleId + TTextLines.LineBreakOf(AText);
end;

class function TAtlasHide.SuppressFile(const AText, ARuleId: string): TAtlasTextInsert;
var
  Lines: TArray<string>;
  Index: Integer;
begin
  Lines := TTextLines.SplitLines(AText);
  for Index := 0 to High(Lines) do
    if ExtendComment(Lines[Index], Index, 'lsp-ignore-file:', ARuleId, Result) then
      Exit;
  Result := Default(TAtlasTextInsert);
  Result.Text := FileMarker + ARuleId + TTextLines.LineBreakOf(AText);
end;

class function TAtlasHide.Plan(const ATarget: TAtlasHideTarget; AScope: TAtlasHideScope;
  const AText, ATeamFolder: string; out APlan: TAtlasHidePlan; out ARefusal: TAtlasHideRefusal): Boolean;
var
  Relative, Anchor: string;
begin
  APlan := Default(TAtlasHidePlan);
  APlan.Target := ATarget;
  APlan.Scope := AScope;
  APlan.SettingKey := ATarget.SettingKey;
  ARefusal := TAtlasHideRefusal.None;
  Result := False;
  if not ATarget.Offers(AScope) then
  begin
    ARefusal := TAtlasHideRefusal.ScopeNotOffered;
    Exit;
  end;
  if AScope = TAtlasHideScope.Everywhere then
  begin
    APlan.Kind := TAtlasHideKind.Setting;
    Exit(True);
  end;
  // Befund mit Regel: Unterdrückungskommentar (#147).
  if (ATarget.Element = TAtlasDrawnElement.Problems) and (ATarget.RuleId <> '') then
  begin
    if AScope = TAtlasHideScope.Here then
    begin
      APlan.Kind := TAtlasHideKind.LineComment;
      APlan.Insert := SuppressLine(AText, ATarget.Line, ATarget.RuleId);
    end
    else
    begin
      APlan.Kind := TAtlasHideKind.FileComment;
      APlan.Insert := SuppressFile(AText, ATarget.RuleId);
    end;
    if APlan.Insert.IsEmpty then
    begin
      ARefusal := TAtlasHideRefusal.AlreadyHidden;
      Exit;
    end;
    Exit(True);
  end;
  // Sonst Eintrag in der Projektdatei.
  if ATeamFolder = '' then
  begin
    ARefusal := TAtlasHideRefusal.NoProjectFolder;
    Exit;
  end;
  if not TAtlasHiddenPlaces.Relative(ATeamFolder, ATarget.FileName, Relative) then
  begin
    ARefusal := TAtlasHideRefusal.OutsideProject;
    Exit;
  end;
  Anchor := '';
  if AScope = TAtlasHideScope.Here then
  begin
    Anchor := ATarget.Anchor;
    // Ohne Anker gäbe es keine einzelne Stelle: dann gilt der Eintrag nur mit Zeilennummer nicht.
    if Anchor = '' then
    begin
      ARefusal := TAtlasHideRefusal.ScopeNotOffered;
      Exit;
    end;
  end;
  APlan.Kind := TAtlasHideKind.TeamFile;
  APlan.Place := TAtlasHiddenPlace.Create(ATarget.SettingKey, Relative, Anchor);
  Result := True;
end;

class function TAtlasHide.IsOn(const ASettings: TAtlasPluginSettings; const AKey: string): Boolean;
var
  Store: IAtlasMemorySettingsStore;
begin
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  if Store.HasInteger(AKey) then
    Result := Store.ReadInteger(AKey, 0) <> 0
  else
    Result := (Store.Text(AKey) <> '') and not SameText(Store.Text(AKey), 'off');
end;

class function TAtlasHide.SwitchOff(var ASettings: TAtlasPluginSettings; const AKey: string;
  out AOldValue: string): Boolean;
var
  Store: IAtlasMemorySettingsStore;
begin
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  AOldValue := Store.Text(AKey);
  Result := (AOldValue <> '') and IsOn(ASettings, AKey);
  if not Result then
    Exit;
  if Store.HasInteger(AKey) then
    Store.WriteInteger(AKey, 0)
  else
    Store.WriteString(AKey, 'off');
  ASettings.Load(Store);
end;

class function TAtlasHide.Restore(var ASettings: TAtlasPluginSettings; const AKey, AOldValue: string): Boolean;
var
  Store: IAtlasMemorySettingsStore;
begin
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Result := Store.Text(AKey) <> '';
  if not Result then
    Exit;
  if Store.HasInteger(AKey) then
    Store.WriteInteger(AKey, StrToIntDef(AOldValue, 1))
  else
    Store.WriteString(AKey, AOldValue);
  ASettings.Load(Store);
end;

end.
