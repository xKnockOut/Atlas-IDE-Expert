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
//   Gekennzeichnete Werte (Atlas.Text.LogMarks, #1478) gehen zuerst: Ein Name
//   wird immer name#N (und gilt danach als bekannt), ein Pfad datei#N, fremder
//   Text wert#N, auch wenn kein Muster sie erkennt. Die Muster danach bleiben
//   als Netz für Zeilen ohne Kennzeichen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.LogMarks;

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
    // Muster einmal übersetzt: vorher je Logzeile vier und je Wert zwei neu. TRegEx ist
    // nicht threadsicher; alle Zugriffe laufen unter FLock (Anonymize).
    FQuoted, FPath, FBackslash, FWord, FNumber, FMethod, FExtension, FDrive: TRegEx;
    function LooksLikePath(const AText: string): Boolean;
    function NameLabel(const AName: string): string;
    function PathLabel(const APath: string): string;
    function QuotedLabel(const AInner: string): string;
    function WordLabel(const AWord: string): string;
    /// <summary>Ersatz für einen gekennzeichneten Wert; unter FLock.</summary>
    function MarkLabel(AKind: TLogMarkKind; const AValue: string): string;
    function ValueLabel(const AValue: string): string;
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
  System.NetEncoding,
  Atlas.Text.Chars;

const
  cIdPrefixes: array[TDiagnosticIdKind] of string = ('proj', 'doc', 'unit');
  cForbiddenExtensions: array[0..6] of string = ('.pas', '.dpr', '.dpk', '.dproj', '.inc', '.dfm', '.groupproj');

{ TDiagnosticIds }

constructor TDiagnosticIds.Create;
var
  mKind: TDiagnosticIdKind;
begin
  inherited Create;
  FLock := TObject.Create;
  for mKind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
  begin
    FIds[mKind] := TDictionary<string, Integer>.Create;
    FNames[mKind] := TList<string>.Create;
  end;
end;

destructor TDiagnosticIds.Destroy;
var
  mKind: TDiagnosticIdKind;
begin
  for mKind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
  begin
    FNames[mKind].Free;
    FIds[mKind].Free;
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
  mKey: string;
  mNumber: Integer;
begin
  mKey := NormalizedPath(AName);
  TMonitor.Enter(FLock);
  try
    if not FIds[AKind].TryGetValue(mKey, mNumber) then
    begin
      FNames[AKind].Add(AName);
      mNumber := FNames[AKind].Count;
      FIds[AKind].Add(mKey, mNumber);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := cIdPrefixes[AKind] + '#' + IntToStr(mNumber);
end;

procedure TDiagnosticIds.SetLibraryRoots(const ARoots: TArray<string>);
var
  mRoots: TArray<string>;
  mRoot: string;
begin
  mRoots := nil;
  for mRoot in ARoots do
  begin
    if Trim(mRoot) <> '' then
    begin
      mRoots := mRoots + [IncludeTrailingPathDelimiter(NormalizedPath(Trim(mRoot))).Replace('/', '\')];
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FLibraryRoots := mRoots;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDiagnosticIds.IsLibraryFile(const AFileName: string): Boolean;
var
  mRoots: TArray<string>;
  mRoot, mName: string;
begin
  TMonitor.Enter(FLock);
  try
    mRoots := FLibraryRoots;
  finally
    TMonitor.Exit(FLock);
  end;
  mName := NormalizedPath(AFileName);
  for mRoot in mRoots do
  begin
    if mName.StartsWith(mRoot) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDiagnosticIds.UnitLabel(const AUnitName, AFileName: string): string;
begin
  if (AFileName <> '') and IsLibraryFile(AFileName) then
  begin
    Result := AUnitName;
  end
  else
  begin
    Result := IdOf(TDiagnosticIdKind.UnitFile, AFileName);
  end;
end;

function TDiagnosticIds.MapLines: TArray<string>;
var
  mKind: TDiagnosticIdKind;
  mIndex: Integer;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for mKind := Low(TDiagnosticIdKind) to High(TDiagnosticIdKind) do
    begin
      for mIndex := 0 to FNames[mKind].Count - 1 do
      begin
        Result := Result + [cIdPrefixes[mKind] + '#' + IntToStr(mIndex + 1) + #9 + FNames[mKind][mIndex]];
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TDiagnosticFilter }

constructor TDiagnosticFilter.Create(const AForbidden: TArray<string>);
var
  mValue: string;
begin
  inherited Create;
  FForbidden := nil;
  for mValue in AForbidden do
  begin
    if Length(Trim(mValue)) >= 3 then
    begin
      FForbidden := FForbidden + [AnsiLowerCase(Trim(mValue))];
    end;
  end;
end;

function TDiagnosticFilter.Clean(const ALine: string): string;
var
  mToken: string;
begin
  Result := ALine;
  for mToken in FAllowed do
  begin
    if mToken <> '' then
    begin
      Result := Result.Replace(mToken, ' ', [rfReplaceAll]);
    end;
  end;
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z']);
end;

/// <summary>Einzelner Buchstabe als ganzes Wort vor einem Doppelpunkt, z. B. "C:".</summary>
function HasDriveLetter(const ALine: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 1 to Length(ALine) - 1 do
  begin
    // Bewusst ASCII: Ein Umlaut davor hebt die Erkennung nicht auf, im Zweifel gilt die Zeile als Pfad.
    if (ALine[mIndex + 1] = ':') and IsLetter(ALine[mIndex]) and
      ((mIndex = 1) or not TTextChars.IsAsciiIdentChar(ALine[mIndex - 1])) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDiagnosticFilter.Accept(const ALine: string): Boolean;
var
  mLine, mLower, mValue: string;
begin
  mLine := Clean(ALine);
  mLower := AnsiLowerCase(mLine);
  Result := (Pos('\', mLine) = 0) and (Pos('/', mLine) = 0) and (Pos('@', mLine) = 0) and not HasDriveLetter(mLine);
  if Result then
  begin
    for mValue in cForbiddenExtensions do
    begin
      if Pos(mValue, mLower) > 0 then
      begin
        Result := False;
        Break;
      end;
    end;
  end;
  if Result then
  begin
    for mValue in FForbidden do
    begin
      if Pos(mValue, mLower) > 0 then
      begin
        Result := False;
        Break;
      end;
    end;
  end;
  if not Result then
  begin
    AtomicIncrement(FDropped);
  end;
end;

class function TDiagnosticFilter.StackFrame(const AFrame: string): string;
begin
  Result := TRegEx.Replace(Trim(AFrame), '\s*\([^()]*:(\d+)\)', ' line $1');
end;

{ TLogAnonymizer }

const
  cQuotedPattern = '"[^"\r\n]*"|''[^''\r\n]*''|„[^“”\r\n]*[“”]';
  cPathPattern = 'file:[^\s"''<>]+|(?:\b[A-Za-z]:|\\\\)[\\/][^\s"''<>|,;()\[\]]*';
  // Rest eines Pfads mit Leerzeichen: jedes Wort mit "\".
  cBackslashPattern = '[^\s"''<>]*\\[^\s"''<>]*';
  cWordPattern = '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*';
  // Bleibt stehen: Zahlen, Zeiten, Größen.
  cNumberPattern = '^[0-9.,:%+\s-]*$';
  // LSP-Methoden wie textDocument/hover oder $/progress.
  cMethodPattern = '^\$?[A-Za-z]*(/[A-Za-z$]+)+$';
  cExtensionPattern = '^\.[a-z0-9]{1,8}$';
  cDrivePattern = '^[A-Za-z]:[\\/]';

type
  TMatchMap = reference to function(const AMatch: string): string;

function ReplaceMatches(const AText: string; const ARegEx: TRegEx; const AMap: TMatchMap): string;
var
  mMatch: TMatch;
  mLast: Integer;
  mBuilder: TStringBuilder;
begin
  // TStringBuilder statt Result := Result + …: lange Zeilen mit vielen Treffern.
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mLast := 1;
    for mMatch in ARegEx.Matches(AText) do
    begin
      mBuilder.Append(Copy(AText, mLast, mMatch.Index - mLast));
      mBuilder.Append(AMap(mMatch.Value));
      mLast := mMatch.Index + mMatch.Length;
    end;
    mBuilder.Append(Copy(AText, mLast, MaxInt));
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TLogAnonymizer.LooksLikePath(const AText: string): Boolean;
begin
  Result := (Pos('\', AText) > 0) or StartsText('file:', AText) or FDrive.IsMatch(AText);
end;

constructor TLogAnonymizer.Create(const AIdentity: TArray<string>);
var
  mValue: string;
begin
  inherited Create;
  FLock := TObject.Create;
  FIds := TDiagnosticIds.Create;
  FPaths := TDictionary<string, Integer>.Create;
  FNames := TDictionary<string, Integer>.Create;
  FValues := TDictionary<string, Integer>.Create;
  // roNotEmpty wie bei den Klassenmethoden von TRegEx, die vorher benutzt wurden.
  FQuoted := TRegEx.Create(cQuotedPattern, [roNotEmpty, roCompiled]);
  FPath := TRegEx.Create(cPathPattern, [roNotEmpty, roCompiled]);
  FBackslash := TRegEx.Create(cBackslashPattern, [roNotEmpty, roCompiled]);
  FWord := TRegEx.Create(cWordPattern, [roNotEmpty, roCompiled]);
  FNumber := TRegEx.Create(cNumberPattern, [roNotEmpty, roCompiled]);
  FMethod := TRegEx.Create(cMethodPattern, [roNotEmpty, roCompiled]);
  FExtension := TRegEx.Create(cExtensionPattern, [roNotEmpty, roCompiled]);
  FDrive := TRegEx.Create(cDrivePattern, [roNotEmpty, roCompiled]);
  FIdentity := nil;
  for mValue in AIdentity do
  begin
    if Length(Trim(mValue)) >= 3 then
    begin
      FIdentity := FIdentity + [Trim(mValue)];
    end;
  end;
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
  mKey: string;
begin
  mKey := AnsiLowerCase(Trim(AName));
  // Kurze Namen wie "A" oder "UI" kämen sonst in jedem Satz vor.
  if (Length(mKey) < 3) or FNames.ContainsKey(mKey) then
  begin
    Exit;
  end;
  FNames.Add(mKey, FNames.Count + 1);
end;

procedure TLogAnonymizer.AddNames(const ANames: TArray<string>);
var
  mName: string;
begin
  TMonitor.Enter(FLock);
  try
    for mName in ANames do
    begin
      AddNameLocked(mName);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogAnonymizer.AddUnit(const AUnitName, AFileName: string);
begin
  if (AFileName <> '') and FIds.IsLibraryFile(AFileName) then
  begin
    Exit;
  end;
  AddNames([AUnitName]);
end;

procedure TLogAnonymizer.SetLibraryRoots(const ARoots: TArray<string>);
begin
  FIds.SetLibraryRoots(ARoots);
end;

function TLogAnonymizer.NameLabel(const AName: string): string;
var
  mNumber: Integer;
begin
  if FNames.TryGetValue(AnsiLowerCase(AName), mNumber) then
  begin
    Result := 'name#' + IntToStr(mNumber);
  end
  else
  begin
    Result := '';
  end;
end;

function TLogAnonymizer.PathLabel(const APath: string): string;
var
  mPath, mKey, mExtension: string;
  mNumber: Integer;
begin
  mPath := APath;
  if StartsText('file:', mPath) then
  begin
    mPath := TNetEncoding.URL.Decode(Copy(mPath, 6, MaxInt));
    while StartsStr('/', mPath) do
    begin
      Delete(mPath, 1, 1);
    end;
    mPath := mPath.Replace('/', '\');
  end;
  if FIds.IsLibraryFile(mPath) then
  begin
    Exit(ExtractFileName(mPath));
  end;
  // Der Dateiname ist oft ein Unit- oder Projektname: auch im übrigen Text verbergen.
  AddNameLocked(ChangeFileExt(ExtractFileName(mPath), ''));
  mKey := AnsiUpperCase(mPath.Replace('/', '\'));
  if not FPaths.TryGetValue(mKey, mNumber) then
  begin
    mNumber := FPaths.Count + 1;
    FPaths.Add(mKey, mNumber);
  end;
  mExtension := AnsiLowerCase(ExtractFileExt(mPath));
  if not FExtension.IsMatch(mExtension) then
  begin
    mExtension := '';
  end;
  Result := 'datei#' + IntToStr(mNumber) + mExtension;
end;

function TLogAnonymizer.ValueLabel(const AValue: string): string;
var
  mNumber: Integer;
begin
  if not FValues.TryGetValue(AValue, mNumber) then
  begin
    mNumber := FValues.Count + 1;
    FValues.Add(AValue, mNumber);
  end;
  Result := 'wert#' + IntToStr(mNumber);
end;

function TLogAnonymizer.MarkLabel(AKind: TLogMarkKind; const AValue: string): string;
begin
  case AKind of
    TLogMarkKind.Name:
      begin
        // Kurze Namen bleiben aus dem Wörterbuch (sie kämen in jedem Satz vor), verborgen werden sie trotzdem.
        AddNameLocked(AValue);
        Result := NameLabel(Trim(AValue));
        if Result = '' then
        begin
          Result := ValueLabel(AValue);
        end;
      end;
    TLogMarkKind.Path:
      Result := PathLabel(Trim(AValue));
  else
    if FNumber.IsMatch(AValue) then
    begin
      Result := AValue;
    end
    else
    begin
      Result := ValueLabel(AValue);
    end;
  end;
end;

function TLogAnonymizer.QuotedLabel(const AInner: string): string;
begin
  if FNumber.IsMatch(AInner) or FMethod.IsMatch(AInner) then
  begin
    Exit(AInner);
  end;
  if LooksLikePath(AInner) then
  begin
    Exit(PathLabel(AInner));
  end;
  Result := NameLabel(Trim(AInner));
  if Result = '' then
  begin
    Result := ValueLabel(AInner);
  end;
end;

function TLogAnonymizer.WordLabel(const AWord: string): string;
var
  mParts: TArray<string>;
  mCount, mIndex, mFirst: Integer;
  mPart: string;
begin
  mParts := AWord.Split(['.']);
  // Längster bekannter Anfang: "Firma.Kunden.TKunde" mit der Unit "Firma.Kunden" wird "name#3.TKunde".
  Result := '';
  mFirst := 0;
  for mCount := Length(mParts) downto 1 do
  begin
    Result := NameLabel(string.Join('.', Copy(mParts, 0, mCount)));
    if Result <> '' then
    begin
      mFirst := mCount;
      Break;
    end;
  end;
  // Die übrigen Teile einzeln, z. B. der Projektname "Kunden".
  for mIndex := mFirst to High(mParts) do
  begin
    mPart := NameLabel(mParts[mIndex]);
    if mPart = '' then
    begin
      mPart := mParts[mIndex];
    end;
    if Result = '' then
    begin
      Result := mPart;
    end
    else
    begin
      Result := Result + '.' + mPart;
    end;
  end;
end;

function TLogAnonymizer.Anonymize(const AText: string): string;
var
  mIndex: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := TLogMarks.Resolve(AText,
      function(AKind: TLogMarkKind; const AValue: string): string
      begin
        Result := MarkLabel(AKind, AValue);
      end);
    for mIndex := 0 to High(FIdentity) do
    begin
      Result := StringReplace(Result, FIdentity[mIndex], 'benutzer#' + IntToStr(mIndex + 1),
        [rfReplaceAll, rfIgnoreCase]);
    end;
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
