unit Atlas.Common.Diagnostics.Anonymizer;

// Anonymisierung für das Diagnoselog (#647).
// - TDiagnosticIds ersetzt Pfade und Namen durch Kurz-IDs (proj#1, doc#4,
//   unit#118), stabil innerhalb eines Laufs. Die Zuordnung ID → Name hält es
//   im Speicher; geschrieben wird sie nur auf Wunsch (diagnostics.log.mapFile).
//   Units aus der Delphi-Installation (RTL, VCL) dürfen mit Namen erscheinen;
//   erkannt am Bibliothekspfad, nicht am Namen.
// - TDiagnosticFilter prüft jede Zeile vor dem Schreiben. Laufwerksbuchstaben,
//   "\", "/", Dateiendungen von Delphi-Quellen, "@", Benutzer- und Rechnername
//   verwerfen die Zeile; gezählt wird, wie viele verworfen wurden.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TDiagnosticIdKind = (Project, Document, UnitFile);

  TDiagnosticIds = class
  private
    FLock: TObject;
    FIds: array[TDiagnosticIdKind] of TDictionary<string, Integer>;
    FNames: array[TDiagnosticIdKind] of TList<string>;
    FLibraryRoots: TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Kurz-ID zu AName, z. B. "doc#4"; dieselbe Datei bekommt im Lauf immer dieselbe.</summary>
    function IdOf(AKind: TDiagnosticIdKind; const AName: string): string;
    /// <summary>Name der Unit, wenn ihre Datei unter einem Bibliothekspfad liegt, sonst ihre Kurz-ID.</summary>
    function UnitLabel(const AUnitName, AFileName: string): string;
    /// <summary>True, wenn AFileName unter einem der Bibliothekspfade liegt.</summary>
    function IsLibraryFile(const AFileName: string): Boolean;
    /// <summary>Zuordnung als Zeilen "ID&lt;TAB&gt;Name" für die lokale Map-Datei.</summary>
    function MapLines: TArray<string>;
    /// <summary>Ordner der Delphi-Installation (z. B. $(BDS)\source).</summary>
    procedure SetLibraryRoots(const ARoots: TArray<string>);
  end;

  TDiagnosticFilter = class
  private
    FForbidden: TArray<string>;
    FAllowed: TArray<string>;
    FDropped: Integer;
    function Clean(const ALine: string): string;
  public
    /// <summary>AForbidden: Benutzer- und Rechnername u. ä.; Einträge unter drei Zeichen zählen nicht.</summary>
    constructor Create(const AForbidden: TArray<string>);
    /// <summary>True, wenn die Zeile geschrieben werden darf; sonst zählt Dropped hoch.</summary>
    function Accept(const ALine: string): Boolean;
    /// <summary>Rahmen eines Aufrufstapels ohne Quelldatei: "Unit.Routine (Unit.pas:12)" wird
    /// zu "Unit.Routine line 12"; sonst verwürfe der Filter den Rahmen wegen der Endung.</summary>
    class function StackFrame(const AFrame: string): string; static;
    /// <summary>Feste Bezeichner des Servers, die "/" enthalten dürfen (LSP-Methoden wie textDocument/hover).</summary>
    property Allowed: TArray<string> read FAllowed write FAllowed;
    property Dropped: Integer read FDropped;
  end;

implementation

uses
  System.RegularExpressions;

const
  IdPrefixes: array[TDiagnosticIdKind] of string = ('proj', 'doc', 'unit');
  ForbiddenExtensions: array[0..6] of string = ('.pas', '.dpr', '.dpk', '.dproj', '.inc', '.dfm', '.groupproj');

{ TDiagnosticIds }

constructor TDiagnosticIds.Create;
var
  Kind: TDiagnosticIdKind;
begin
  inherited Create;
  FLock := TObject.Create;
  for Kind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
  begin
    FIds[Kind] := TDictionary<string, Integer>.Create;
    FNames[Kind] := TList<string>.Create;
  end;
end;

destructor TDiagnosticIds.Destroy;
var
  Kind: TDiagnosticIdKind;
begin
  for Kind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
  begin
    FNames[Kind].Free;
    FIds[Kind].Free;
  end;
  FLock.Free;
  inherited;
end;

function NormalizedPath(const AName: string): string;
begin
  Result := AnsiUpperCase(AName.Replace('/', '\'));
end;

function TDiagnosticIds.IdOf(AKind: TDiagnosticIdKind; const AName: string): string;
var
  Key: string;
  Number: Integer;
begin
  Key := NormalizedPath(AName);
  TMonitor.Enter(FLock);
  try
    if not FIds[AKind].TryGetValue(Key, Number) then
    begin
      FNames[AKind].Add(AName);
      Number := FNames[AKind].Count;
      FIds[AKind].Add(Key, Number);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := IdPrefixes[AKind] + '#' + IntToStr(Number);
end;

procedure TDiagnosticIds.SetLibraryRoots(const ARoots: TArray<string>);
var
  Roots: TArray<string>;
  Root: string;
begin
  Roots := nil;
  for Root in ARoots do
    if Trim(Root) <> '' then
      Roots := Roots + [IncludeTrailingPathDelimiter(NormalizedPath(Trim(Root))).Replace('/', '\')];
  TMonitor.Enter(FLock);
  try
    FLibraryRoots := Roots;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDiagnosticIds.IsLibraryFile(const AFileName: string): Boolean;
var
  Roots: TArray<string>;
  Root, Name: string;
begin
  TMonitor.Enter(FLock);
  try
    Roots := FLibraryRoots;
  finally
    TMonitor.Exit(FLock);
  end;
  Name := NormalizedPath(AFileName);
  for Root in Roots do
    if Name.StartsWith(Root) then
      Exit(True);
  Result := False;
end;

function TDiagnosticIds.UnitLabel(const AUnitName, AFileName: string): string;
begin
  if (AFileName <> '') and IsLibraryFile(AFileName) then
    Result := AUnitName
  else
    Result := IdOf(TDiagnosticIdKind.UnitFile, AFileName);
end;

function TDiagnosticIds.MapLines: TArray<string>;
var
  Kind: TDiagnosticIdKind;
  Index: Integer;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for Kind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
      for Index := 0 to FNames[Kind].Count - 1 do
        Result := Result + [IdPrefixes[Kind] + '#' + IntToStr(Index + 1) + #9 + FNames[Kind][Index]];
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TDiagnosticFilter }

constructor TDiagnosticFilter.Create(const AForbidden: TArray<string>);
var
  Value: string;
begin
  inherited Create;
  FForbidden := nil;
  for Value in AForbidden do
    if Length(Trim(Value)) >= 3 then
      FForbidden := FForbidden + [AnsiLowerCase(Trim(Value))];
end;

function TDiagnosticFilter.Clean(const ALine: string): string;
var
  Token: string;
begin
  Result := ALine;
  for Token in FAllowed do
    if Token <> '' then
      Result := Result.Replace(Token, ' ', [rfReplaceAll]);
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z']);
end;

function IsWordChar(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

/// <summary>Einzelner Buchstabe als ganzes Wort vor einem Doppelpunkt, z. B. "C:".</summary>
function HasDriveLetter(const ALine: string): Boolean;
var
  Index: Integer;
begin
  for Index := 1 to Length(ALine) - 1 do
    if (ALine[Index + 1] = ':') and IsLetter(ALine[Index]) and ((Index = 1) or not IsWordChar(ALine[Index - 1])) then
      Exit(True);
  Result := False;
end;

function TDiagnosticFilter.Accept(const ALine: string): Boolean;
var
  Line, Lower, Value: string;
begin
  Line := Clean(ALine);
  Lower := AnsiLowerCase(Line);
  Result := (Pos('\', Line) = 0) and (Pos('/', Line) = 0) and (Pos('@', Line) = 0) and not HasDriveLetter(Line);
  if Result then
    for Value in ForbiddenExtensions do
      if Pos(Value, Lower) > 0 then
      begin
        Result := False;
        Break;
      end;
  if Result then
    for Value in FForbidden do
      if Pos(Value, Lower) > 0 then
      begin
        Result := False;
        Break;
      end;
  if not Result then
    AtomicIncrement(FDropped);
end;

class function TDiagnosticFilter.StackFrame(const AFrame: string): string;
begin
  Result := TRegEx.Replace(Trim(AFrame), '\s*\([^()]*:(\d+)\)', ' line $1');
end;

end.
