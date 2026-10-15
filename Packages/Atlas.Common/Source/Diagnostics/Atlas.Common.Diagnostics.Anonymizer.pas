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
// - TLogAnonymizer schreibt Zeilen des Server-Logs (--log) um, statt sie zu
//   verwerfen: Pfade werden zu datei#N, Namen aus Projekten und
//   Arbeitsbereichen zu name#N, Text in Anführungszeichen zu wert#N, Benutzer-
//   und Rechnername zu benutzer#N. Dateien unter den Bibliothekspfaden der
//   Delphi-Installation behalten ihren Namen. Die Nummern gelten für einen Lauf.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions;

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

  /// <summary>Anonymisiert Zeilen des Server-Logs (#647). Threadsicher.</summary>
  ILogAnonymizer = interface
    ['{6C2F4E81-3B7A-4D59-A1E6-9F0B3C7D2E14}']
    function Anonymize(const AText: string): string;
    /// <summary>Namen, die nie im Klartext erscheinen dürfen (Projekte, Ordner, Units des Projekts).</summary>
    procedure AddNames(const ANames: TArray<string>);
    /// <summary>Wie AddNames, aber nicht für Units unter einem Bibliothekspfad.</summary>
    procedure AddUnit(const AUnitName, AFileName: string);
    procedure SetLibraryRoots(const ARoots: TArray<string>);
  end;

  TLogAnonymizer = class(TInterfacedObject, ILogAnonymizer)
  private
    FLock: TObject;
    FIds: TDiagnosticIds;
    FPaths: TDictionary<string, Integer>;
    FNames: TDictionary<string, Integer>;
    FValues: TDictionary<string, Integer>;
    FIdentity: TArray<string>;
    // Muster einmal übersetzt (Code-Review P-11): vorher je Logzeile vier und je Wert zwei neu. TRegEx ist
    // nicht threadsicher; alle Zugriffe laufen unter FLock (Anonymize).
    FQuoted, FPath, FBackslash, FWord, FNumber, FMethod, FExtension, FDrive: TRegEx;
    function LooksLikePath(const AText: string): Boolean;
    function NameLabel(const AName: string): string;
    function PathLabel(const APath: string): string;
    function QuotedLabel(const AInner: string): string;
    function WordLabel(const AWord: string): string;
    procedure AddNameLocked(const AName: string);
  public
    /// <summary>AIdentity: Benutzer- und Rechnername u. ä.; Einträge unter drei Zeichen zählen nicht.</summary>
    constructor Create(const AIdentity: TArray<string>);
    destructor Destroy; override;
    function Anonymize(const AText: string): string;
    procedure AddNames(const ANames: TArray<string>);
    procedure AddUnit(const AUnitName, AFileName: string);
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
  System.StrUtils,
  System.NetEncoding;

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

{ TLogAnonymizer }

const
  QuotedPattern = '"[^"\r\n]*"|''[^''\r\n]*''|„[^“”\r\n]*[“”]';
  PathPattern = 'file:[^\s"''<>]+|(?:\b[A-Za-z]:|\\\\)[\\/][^\s"''<>|,;()\[\]]*';
  // Rest eines Pfads mit Leerzeichen: jedes Wort mit "\".
  BackslashPattern = '[^\s"''<>]*\\[^\s"''<>]*';
  WordPattern = '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*';
  // Bleibt stehen: Zahlen, Zeiten, Größen.
  NumberPattern = '^[0-9.,:%+\s-]*$';
  // LSP-Methoden wie textDocument/hover oder $/progress.
  MethodPattern = '^\$?[A-Za-z]*(/[A-Za-z$]+)+$';
  ExtensionPattern = '^\.[a-z0-9]{1,8}$';
  DrivePattern = '^[A-Za-z]:[\\/]';

type
  TMatchMap = reference to function(const AMatch: string): string;

function ReplaceMatches(const AText: string; const ARegEx: TRegEx; const AMap: TMatchMap): string;
var
  Match: TMatch;
  Last: Integer;
  Builder: TStringBuilder;
begin
  // TStringBuilder statt Result := Result + … (Code-Review P-11): lange Zeilen mit vielen Treffern.
  Builder := TStringBuilder.Create(Length(AText));
  try
    Last := 1;
    for Match in ARegEx.Matches(AText) do
    begin
      Builder.Append(Copy(AText, Last, Match.Index - Last));
      Builder.Append(AMap(Match.Value));
      Last := Match.Index + Match.Length;
    end;
    Builder.Append(Copy(AText, Last, MaxInt));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TLogAnonymizer.LooksLikePath(const AText: string): Boolean;
begin
  Result := (Pos('\', AText) > 0) or StartsText('file:', AText) or FDrive.IsMatch(AText);
end;

constructor TLogAnonymizer.Create(const AIdentity: TArray<string>);
var
  Value: string;
begin
  inherited Create;
  FLock := TObject.Create;
  FIds := TDiagnosticIds.Create;
  FPaths := TDictionary<string, Integer>.Create;
  FNames := TDictionary<string, Integer>.Create;
  FValues := TDictionary<string, Integer>.Create;
  // roNotEmpty wie bei den Klassenmethoden von TRegEx, die vorher benutzt wurden.
  FQuoted := TRegEx.Create(QuotedPattern, [roNotEmpty, roCompiled]);
  FPath := TRegEx.Create(PathPattern, [roNotEmpty, roCompiled]);
  FBackslash := TRegEx.Create(BackslashPattern, [roNotEmpty, roCompiled]);
  FWord := TRegEx.Create(WordPattern, [roNotEmpty, roCompiled]);
  FNumber := TRegEx.Create(NumberPattern, [roNotEmpty, roCompiled]);
  FMethod := TRegEx.Create(MethodPattern, [roNotEmpty, roCompiled]);
  FExtension := TRegEx.Create(ExtensionPattern, [roNotEmpty, roCompiled]);
  FDrive := TRegEx.Create(DrivePattern, [roNotEmpty, roCompiled]);
  FIdentity := nil;
  for Value in AIdentity do
    if Length(Trim(Value)) >= 3 then
      FIdentity := FIdentity + [Trim(Value)];
end;

destructor TLogAnonymizer.Destroy;
begin
  FValues.Free;
  FNames.Free;
  FPaths.Free;
  FIds.Free;
  FLock.Free;
  inherited;
end;

procedure TLogAnonymizer.AddNameLocked(const AName: string);
var
  Key: string;
begin
  Key := AnsiLowerCase(Trim(AName));
  // Kurze Namen wie "A" oder "UI" kämen sonst in jedem Satz vor.
  if (Length(Key) < 3) or FNames.ContainsKey(Key) then
    Exit;
  FNames.Add(Key, FNames.Count + 1);
end;

procedure TLogAnonymizer.AddNames(const ANames: TArray<string>);
var
  Name: string;
begin
  TMonitor.Enter(FLock);
  try
    for Name in ANames do
      AddNameLocked(Name);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogAnonymizer.AddUnit(const AUnitName, AFileName: string);
begin
  if (AFileName <> '') and FIds.IsLibraryFile(AFileName) then
    Exit;
  AddNames([AUnitName]);
end;

procedure TLogAnonymizer.SetLibraryRoots(const ARoots: TArray<string>);
begin
  FIds.SetLibraryRoots(ARoots);
end;

function TLogAnonymizer.NameLabel(const AName: string): string;
var
  Number: Integer;
begin
  if FNames.TryGetValue(AnsiLowerCase(AName), Number) then
    Result := 'name#' + IntToStr(Number)
  else
    Result := '';
end;

function TLogAnonymizer.PathLabel(const APath: string): string;
var
  Path, Key, Extension: string;
  Number: Integer;
begin
  Path := APath;
  if StartsText('file:', Path) then
  begin
    Path := TNetEncoding.URL.Decode(Copy(Path, 6, MaxInt));
    while StartsStr('/', Path) do
      Delete(Path, 1, 1);
    Path := Path.Replace('/', '\');
  end;
  if FIds.IsLibraryFile(Path) then
    Exit(ExtractFileName(Path));
  // Der Dateiname ist oft ein Unit- oder Projektname: auch im übrigen Text verbergen.
  AddNameLocked(ChangeFileExt(ExtractFileName(Path), ''));
  Key := AnsiUpperCase(Path.Replace('/', '\'));
  if not FPaths.TryGetValue(Key, Number) then
  begin
    Number := FPaths.Count + 1;
    FPaths.Add(Key, Number);
  end;
  Extension := AnsiLowerCase(ExtractFileExt(Path));
  if not FExtension.IsMatch(Extension) then
    Extension := '';
  Result := 'datei#' + IntToStr(Number) + Extension;
end;

function TLogAnonymizer.QuotedLabel(const AInner: string): string;
var
  Number: Integer;
begin
  if FNumber.IsMatch(AInner) or FMethod.IsMatch(AInner) then
    Exit(AInner);
  if LooksLikePath(AInner) then
    Exit(PathLabel(AInner));
  Result := NameLabel(Trim(AInner));
  if Result <> '' then
    Exit;
  if not FValues.TryGetValue(AInner, Number) then
  begin
    Number := FValues.Count + 1;
    FValues.Add(AInner, Number);
  end;
  Result := 'wert#' + IntToStr(Number);
end;

function TLogAnonymizer.WordLabel(const AWord: string): string;
var
  Parts: TArray<string>;
  Count, Index, First: Integer;
  Part: string;
begin
  Parts := AWord.Split(['.']);
  // Längster bekannter Anfang: "Firma.Kunden.TKunde" mit der Unit "Firma.Kunden" wird "name#3.TKunde".
  Result := '';
  First := 0;
  for Count := Length(Parts) downto 1 do
  begin
    Result := NameLabel(string.Join('.', Copy(Parts, 0, Count)));
    if Result <> '' then
    begin
      First := Count;
      Break;
    end;
  end;
  // Die übrigen Teile einzeln, z. B. der Projektname "Kunden".
  for Index := First to High(Parts) do
  begin
    Part := NameLabel(Parts[Index]);
    if Part = '' then
      Part := Parts[Index];
    if Result = '' then
      Result := Part
    else
      Result := Result + '.' + Part;
  end;
end;

function TLogAnonymizer.Anonymize(const AText: string): string;
var
  Index: Integer;
begin
  Result := AText;
  TMonitor.Enter(FLock);
  try
    for Index := 0 to High(FIdentity) do
      Result := StringReplace(Result, FIdentity[Index], 'benutzer#' + IntToStr(Index + 1),
        [rfReplaceAll, rfIgnoreCase]);
    Result := ReplaceMatches(Result, FQuoted,
      function(const AMatch: string): string
      var
        Inner: string;
      begin
        Inner := Copy(AMatch, 2, Length(AMatch) - 2);
        Result := AMatch[1] + QuotedLabel(Inner) + AMatch[Length(AMatch)];
      end);
    Result := ReplaceMatches(Result, FPath,
      function(const AMatch: string): string
      begin
        Result := PathLabel(AMatch);
      end);
    Result := ReplaceMatches(Result, FBackslash,
      function(const AMatch: string): string
      begin
        Result := PathLabel(AMatch);
      end);
    Result := ReplaceMatches(Result, FWord,
      function(const AMatch: string): string
      begin
        Result := WordLabel(AMatch);
      end);
  finally
    TMonitor.Exit(FLock);
  end;
end;

initialization
  // TNetEncoding.URL entsteht sonst beim ersten Dekodieren (oft in einem Test) und zählt dort als Leck.
  TNetEncoding.URL.Decode('');

end.
