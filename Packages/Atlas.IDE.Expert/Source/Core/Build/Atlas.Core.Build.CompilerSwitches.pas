unit Atlas.Core.Build.CompilerSwitches;

// Fenster „Compiler-Schalter“ (#558), Kern ohne VCL und Open Tools API:
//   - TAtlasCompilerSwitchView liest die Antwort von atlas/compilerSwitches
//     (Atlas.Common.Lsp.CompilerSwitches) in Zeilen je Abschnitt: Schalter
//     (R, Q, O, C, I, A), Hinweise und Warnungen (HINTS, WARNINGS, einzelne
//     Warnungen), bedingte Symbole und Ziel (Plattform, Konfiguration).
//   - Je Zeile Wert, Stand der .dproj, Abweichung und Herkunft; mit Datei und
//     Zeile springt ein Doppelklick zur Direktive, mit Projektoption öffnet er
//     die Projektoptionen.
//   - TAtlasSwitchFollow entprellt die Cursorbewegung: Erst DelayMs nach der
//     letzten Änderung von Datei, Zeile oder Spalte fragt Atlas den Server.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasSwitchSection = (Switches, Messages, Defines, Target);
  TAtlasSwitchOriginKind = (Default, Project, Directive, Include);
  {$SCOPEDENUMS OFF}

  TAtlasSwitchRow = record
    Section: TAtlasSwitchSection;
    /// <summary>"R", "HINTS", Bezeichner einer Warnung, Symbol bzw. "platform"/"configuration" im Ziel.</summary>
    Name: string;
    /// <summary>"RANGECHECKS", "ALIGN"; '' sonst.</summary>
    LongName: string;
    /// <summary>"+", "-", "8", "ON", "OFF", "ERROR"; Plattform bzw. Konfiguration im Ziel; '' bei Symbolen.</summary>
    Value: string;
    ProjectValue: string;
    Deviates: Boolean;
    Kind: TAtlasSwitchOriginKind;
    /// <summary>Eigenschaft der .dproj, Direktive ("{$R-}") bzw. Herkunft eines Symbols.</summary>
    OriginText: string;
    FileName: string;
    /// <summary>Zeile der Direktive, 0-basiert; -1 ohne.</summary>
    Line: Integer;
    /// <summary>Datei und Zeile bekannt: Doppelklick springt zur Direktive.</summary>
    function CanJump: Boolean;
    /// <summary>Wert aus der .dproj: Doppelklick öffnet die Projektoptionen.</summary>
    function FromProject: Boolean;
  end;

  TAtlasSwitchRows = TArray<TAtlasSwitchRow>;

  TAtlasCompilerSwitchView = record
    Configuration: string;
    Platform: string;
    HasProject: Boolean;
    /// <summary>Nur Abweichungen von der .dproj („R− Q− HINTS OFF“); '' ohne.</summary>
    Summary: string;
    Rows: TAtlasSwitchRows;
    /// <summary>Antwort von atlas/compilerSwitches; False bei null oder unlesbarer Antwort.</summary>
    class function FromJson(const AValue: TJSONValue; out AView: TAtlasCompilerSwitchView): Boolean; static;
    /// <summary>Zeilen, die von der .dproj abweichen.</summary>
    function Deviations: TAtlasSwitchRows;
  end;

  TAtlasCompilerSwitchTexts = record
    /// <summary>Wert zum Anzeigen: "-" als typografisches Minus (U+2212), sonst unverändert.</summary>
    class function Value(const AValue: string): string; static;
  end;

  /// <summary>Entprellt die Cursorbewegung (#558: 150 ms). Zeiten in ms (GetTickCount64).</summary>
  TAtlasSwitchFollow = class
  public const
    DelayMs = 150;
  private
    FFileName: string;
    FLine: Integer;
    FCharacter: Integer;
    FChangedAt: UInt64;
    FPending: Boolean;
    FImmediate: Boolean;
  public
    constructor Create;
    /// <summary>Cursor an AFileName, ALine, ACharacter um ANow; True, wenn er sich bewegt hat.</summary>
    function Moved(const AFileName: string; ALine, ACharacter: Integer; ANow: UInt64): Boolean;
    /// <summary>Seit DelayMs ruhig und noch nicht abgefragt: True und ab dann nicht mehr fällig.</summary>
    function Due(ANow: UInt64): Boolean;
    /// <summary>Beim nächsten Due sofort abfragen (Fenster geöffnet, Einstellung geändert).</summary>
    procedure Invalidate;
    /// <summary>Datei, für die der Präprozessor Schalter kennt (.pas, .dpr, .dpk, .inc).</summary>
    class function Applies(const AFileName: string): Boolean; static;
    property FileName: string read FFileName;
    property Line: Integer read FLine;
    property Character: Integer read FCharacter;
  end;

implementation

const
  OriginKinds: array[TAtlasSwitchOriginKind] of string = ('default', 'project', 'directive', 'include');

function KindOf(const AText: string): TAtlasSwitchOriginKind;
var
  Kind: TAtlasSwitchOriginKind;
begin
  Result := TAtlasSwitchOriginKind.Default;
  for Kind := Low(TAtlasSwitchOriginKind) to High(TAtlasSwitchOriginKind) do
    if OriginKinds[Kind] = AText then
      Result := Kind;
end;

function RowOf(ASection: TAtlasSwitchSection; AEntry: TJSONObject): TAtlasSwitchRow;
var
  Origin: TJSONObject;
begin
  Result := Default(TAtlasSwitchRow);
  Result.Section := ASection;
  Result.Line := -1;
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.LongName := AEntry.GetValue<string>('longName', '');
  Result.Value := AEntry.GetValue<string>('value', '');
  Result.ProjectValue := AEntry.GetValue<string>('projectValue', '');
  Result.Deviates := AEntry.GetValue<Boolean>('deviates', False);
  if AEntry.TryGetValue<TJSONObject>('origin', Origin) then
  begin
    Result.Kind := KindOf(Origin.GetValue<string>('kind', ''));
    Result.OriginText := Origin.GetValue<string>('text', '');
    Result.FileName := Origin.GetValue<string>('file', '');
    Result.Line := Origin.GetValue<Integer>('line', -1);
  end;
end;

procedure AddRows(var ARows: TAtlasSwitchRows; ASection: TAtlasSwitchSection; const AObject: TJSONObject;
  const AName: string);
var
  Value: TJSONValue;
  Item: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    ARows := ARows + [RowOf(ASection, TJSONObject(Value))]
  else if Value is TJSONArray then
    for Item in TJSONArray(Value) do
      if Item is TJSONObject then
        ARows := ARows + [RowOf(ASection, TJSONObject(Item))];
end;

function TargetRow(const AName, AValue: string): TAtlasSwitchRow;
begin
  Result := Default(TAtlasSwitchRow);
  Result.Section := TAtlasSwitchSection.Target;
  Result.Name := AName;
  Result.Value := AValue;
  Result.ProjectValue := AValue;
  Result.Kind := TAtlasSwitchOriginKind.Project;
  Result.Line := -1;
end;

{ TAtlasSwitchRow }

function TAtlasSwitchRow.CanJump: Boolean;
begin
  Result := (FileName <> '') and (Line >= 0) and
    ((Kind = TAtlasSwitchOriginKind.Directive) or (Kind = TAtlasSwitchOriginKind.Include));
end;

function TAtlasSwitchRow.FromProject: Boolean;
begin
  Result := Kind = TAtlasSwitchOriginKind.Project;
end;

{ TAtlasCompilerSwitchView }

class function TAtlasCompilerSwitchView.FromJson(const AValue: TJSONValue;
  out AView: TAtlasCompilerSwitchView): Boolean;
var
  Root: TJSONObject;
begin
  AView := Default(TAtlasCompilerSwitchView);
  Result := AValue is TJSONObject;
  if not Result then
    Exit;
  Root := TJSONObject(AValue);
  AView.Configuration := Root.GetValue<string>('configuration', '');
  AView.Platform := Root.GetValue<string>('platform', '');
  AView.HasProject := Root.GetValue<Boolean>('hasProject', False);
  AView.Summary := Root.GetValue<string>('summary', '');
  AddRows(AView.Rows, TAtlasSwitchSection.Switches, Root, 'switches');
  AddRows(AView.Rows, TAtlasSwitchSection.Messages, Root, 'hints');
  AddRows(AView.Rows, TAtlasSwitchSection.Messages, Root, 'warnings');
  AddRows(AView.Rows, TAtlasSwitchSection.Messages, Root, 'warns');
  AddRows(AView.Rows, TAtlasSwitchSection.Defines, Root, 'defines');
  if AView.HasProject then
  begin
    AView.Rows := AView.Rows + [TargetRow('platform', AView.Platform)];
    AView.Rows := AView.Rows + [TargetRow('configuration', AView.Configuration)];
  end;
end;

function TAtlasCompilerSwitchView.Deviations: TAtlasSwitchRows;
var
  Row: TAtlasSwitchRow;
begin
  Result := nil;
  for Row in Rows do
    if Row.Deviates then
      Result := Result + [Row];
end;

{ TAtlasCompilerSwitchTexts }

class function TAtlasCompilerSwitchTexts.Value(const AValue: string): string;
begin
  if AValue = '-' then
    Result := #$2212
  else
    Result := AValue;
end;

{ TAtlasSwitchFollow }

constructor TAtlasSwitchFollow.Create;
begin
  inherited Create;
  FLine := -1;
  FCharacter := -1;
end;

function TAtlasSwitchFollow.Moved(const AFileName: string; ALine, ACharacter: Integer; ANow: UInt64): Boolean;
begin
  Result := not SameText(AFileName, FFileName) or (ALine <> FLine) or (ACharacter <> FCharacter);
  if not Result then
    Exit;
  FFileName := AFileName;
  FLine := ALine;
  FCharacter := ACharacter;
  FChangedAt := ANow;
  FPending := True;
end;

function TAtlasSwitchFollow.Due(ANow: UInt64): Boolean;
begin
  Result := FPending and (FImmediate or (ANow < FChangedAt) or (ANow - FChangedAt >= DelayMs));
  if Result then
  begin
    FPending := False;
    FImmediate := False;
  end;
end;

class function TAtlasSwitchFollow.Applies(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc');
end;

procedure TAtlasSwitchFollow.Invalidate;
begin
  FPending := True;
  FImmediate := True;
end;

end.
