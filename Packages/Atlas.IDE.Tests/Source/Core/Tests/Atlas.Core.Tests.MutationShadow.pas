unit Atlas.Core.Tests.MutationShadow;

// Schattenprojekt für den Mutationslauf (#1460), ohne VCL und Open Tools API.
// Die Probe in der IDE hat gezeigt: Ein Testprojekt mit anderem Namen, das die
// mutierte Kopie einer Unit über „in 'Src\X.pas'“ einbindet, lässt sich in der
// Projektgruppe des Benutzers bauen, ohne das Original oder seine DCUs zu
// berühren. Diese Unit baut die Texte dafür, das Plugin schreibt sie:
//   <Projektordner>\.atlas-local\mutation\<Projekt>\
//     <Projekt>Mutation.dpr / .dproj
//     Src\<Unit>.pas          mutierte Kopie (dazu .dfm/.fmx der Unit)
//     Out\, Out\Dcu\          Ausgaben, getrennt vom Original
// dpr: Programmname ersetzt; alle „in '…'“-Pfade und {$R}/{$I} absolut
// zum Ordner des Originals, die mutierte Unit nach Src\ (steht sie nicht in
// der dpr, wird sie an die uses-Klausel angehängt); {$R *.res} zeigt auf die
// .res des Originals oder fällt weg, wenn es keine gibt.
// dproj: MainSource, Projektname und GUID neu; relative Pfade (Suchpfade,
// Include= der Einträge, Symbol, Manifest) absolut; der Ordner des Originals
// und der der Unit stehen vorn im Such- und Include-Pfad (die Kopie liegt
// woanders, die Nachbarn sollen sich weiter finden); Ausgaben nach Out\;
// Ereignisse vor und nach dem Bauen geleert, weil sie Dateien des Originals
// überschreiben könnten.
// Pfade sind Windows-Pfade; die Funktionen arbeiten nur auf Zeichenketten.

interface

type
  /// <summary>Was das Schattenprojekt braucht.</summary>
  TAtlasMutationShadowSource = record
    /// <summary>Voller Pfad der .dproj des Testprojekts.</summary>
    ProjectFile: string;
    /// <summary>Texte von .dpr und .dproj.</summary>
    Dpr: string;
    Dproj: string;
    /// <summary>Name und voller Pfad der mutierten Unit.</summary>
    UnitName: string;
    UnitFile: string;
    /// <summary>GUID des Schattenprojekts ("{…}"), damit die IDE es vom Original unterscheidet.</summary>
    Guid: string;
    /// <summary>Gibt es die .res des Originals?</summary>
    ResExists: Boolean;
  end;

  /// <summary>Dateien und Texte des Schattenprojekts.</summary>
  TAtlasMutationShadow = record
    Folder: string;
    Name: string;
    DprFile: string;
    DprojFile: string;
    /// <summary>Ziel der mutierten Kopie (Src\Name.pas).</summary>
    UnitFile: string;
    Dpr: string;
    Dproj: string;
  end;

  TAtlasMutationShadows = class
  public const
    cLocalFolder = '.atlas-local';
    cMutationFolder = 'mutation';
    cSuffix = 'Mutation';
    cSourceFolder = 'Src';
    cOutFolder = 'Out';
    cDcuFolder = 'Out\Dcu';
  public
    /// <summary>Ordner der Mutationsdaten eines Testprojekts (.atlas-local\mutation).</summary>
    class function DataFolderOf(const AProjectFile: string): string; static;
    /// <summary>Schattenprojekt zu ASource. False, wenn die dpr keinen Programmkopf hat.</summary>
    class function Build(const ASource: TAtlasMutationShadowSource; out AShadow: TAtlasMutationShadow): Boolean;
      static;
    /// <summary>Formulardateien, die mit der Unit AUnitFile kopiert werden müssen, falls es sie gibt.</summary>
    class function CompanionFiles(const AUnitFile: string): TArray<string>; static;
    /// <summary>Ist APath absolut (Laufwerk, \\Server, \) oder beginnt mit einer Variablen ($(…), %…%)?</summary>
    class function IsRooted(const APath: string): Boolean; static;
    /// <summary>APath relativ zu ABase aufgelöst und normalisiert; Wurzelpfade bleiben, wie sie sind.</summary>
    class function Absolute(const ABase, APath: string): string; static;
    /// <summary>APath mit "" als Trenner, ohne "." und "..", ohne abschließenden Trenner.</summary>
    class function Normalized(const APath: string): string; static;
    /// <summary>Ordner der Datei AFileName ohne abschließenden Trenner.</summary>
    class function FolderOf(const AFileName: string): string; static;
    /// <summary>Dateiname ohne Ordner.</summary>
    class function FileNameOf(const AFileName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cBreak = #13#10;
  cUncPrefix = '\\';
  /// <summary>Elemente der dproj mit einer Liste von Pfaden.</summary>
  cPathLists: array[0..3] of string = ('DCC_UnitSearchPath', 'DCC_IncludePath', 'DCC_ResourcePath',
    'DCC_ObjPath');
  /// <summary>Elemente der dproj mit einem Pfad.</summary>
  cPathSingles: array[0..1] of string = ('Icon_MainIcon', 'Manifest_File');
  /// <summary>Ausgaben, die in Out\Dcu umziehen (DCC_ExeOutput geht nach Out).</summary>
  cOutputs: array[0..5] of string = ('DCC_DcuOutput', 'DCC_BplOutput', 'DCC_DcpOutput', 'DCC_HppOutput',
    'DCC_ObjOutput', 'DCC_BpiOutput');
  cEvents: array[0..2] of string = ('PreBuildEvent', 'PostBuildEvent', 'PreLinkEvent');
  /// <summary>Einträge, deren Include= ein Pfad ist.</summary>
  cIncludeItems: array[0..3] of string = ('DCCReference', 'RcCompile', 'RcItem', 'ResourceCompile');
  cBaseGroup = '<PropertyGroup Condition="''$(Base)''!=''''">';
  cIdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'];

type
  TValueFunc = reference to function(const AValue: string): string;

{ Pfade }

class function TAtlasMutationShadows.IsRooted(const APath: string): Boolean;
begin
  Result := (APath <> '') and (CharInSet(APath[1], ['\', '/', '%']) or StartsStr('$(', APath) or
    ((Length(APath) >= 2) and (APath[2] = ':')));
end;

class function TAtlasMutationShadows.Absolute(const ABase, APath: string): string;
begin
  Result := APath;
  if (Trim(APath) <> '') and not IsRooted(APath) then
  begin
    Result := Normalized(ABase + '\' + APath);
  end;
end;

class function TAtlasMutationShadows.Normalized(const APath: string): string;
var
  mParts, mKept: TArray<string>;
  mPart, mPrefix: string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  mPrefix := '';
  if StartsStr(cUncPrefix, Result) then
  begin
    mPrefix := cUncPrefix;
    Result := Copy(Result, Length(cUncPrefix) + 1, MaxInt);
  end;
  mParts := Result.Split(['\']);
  mKept := nil;
  for mPart in mParts do
  begin
    if (mPart = '') or (mPart = '.') then
    begin
      Continue;
    end;
    // Über das Laufwerk hinaus geht es nicht zurück.
    if (mPart = '..') and (Length(mKept) > 0) then
    begin
      if Length(mKept) > 1 then
      begin
        SetLength(mKept, Length(mKept) - 1);
      end;
      Continue;
    end;
    mKept := mKept + [mPart];
  end;
  Result := mPrefix + string.Join('\', mKept);
end;

class function TAtlasMutationShadows.FolderOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  mIndex := LastDelimiter('\/', AFileName);
  Result := Copy(AFileName, 1, mIndex - 1);
end;

class function TAtlasMutationShadows.FileNameOf(const AFileName: string): string;
begin
  Result := Copy(AFileName, LastDelimiter('\/', AFileName) + 1, MaxInt);
end;

/// <summary>Dateiname ohne Endung.</summary>
function BaseNameOf(const AFileName: string): string;
var
  mDot: Integer;
begin
  Result := TAtlasMutationShadows.FileNameOf(AFileName);
  mDot := LastDelimiter('.', Result);
  if mDot > 1 then
  begin
    Result := Copy(Result, 1, mDot - 1);
  end;
end;

class function TAtlasMutationShadows.DataFolderOf(const AProjectFile: string): string;
begin
  Result := FolderOf(AProjectFile) + '\' + cLocalFolder + '\' + cMutationFolder;
end;

class function TAtlasMutationShadows.CompanionFiles(const AUnitFile: string): TArray<string>;
var
  mBase: string;
begin
  mBase := Copy(AUnitFile, 1, Length(AUnitFile) - Length(ExtractFileExt(AUnitFile)));
  Result := TArray<string>.Create(mBase + '.dfm', mBase + '.fmx');
end;

function XmlEscaped(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
end;

function Quoted(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''''', [rfReplaceAll]) + '''';
end;

{ dpr }

/// <summary>Position (ab 1) des Zeichens hinter dem Kommentar oder der Zeichenkette ab AIndex; AIndex selbst, wenn
/// dort keins beginnt.</summary>
function SkipNoise(const AText: string; AIndex: Integer): Integer;
var
  mClose: Integer;
begin
  Result := AIndex;
  if AText[AIndex] = '{' then
  begin
    mClose := PosEx('}', AText, AIndex);
  end
  else if Copy(AText, AIndex, 2) = '(*' then
  begin
    mClose := PosEx('*)', AText, AIndex) + 1;
  end
  else if Copy(AText, AIndex, 2) = '//' then
  begin
    mClose := PosEx(#10, AText, AIndex);
  end
  else if AText[AIndex] = '''' then
  begin
    mClose := PosEx('''', AText, AIndex + 1);
  end
  else
  begin
    Exit;
  end;
  Result := Length(AText) + 1;
  if mClose > 0 then
  begin
    Result := mClose + 1;
  end;
end;

/// <summary>Position (ab 1) des Worts AWord außerhalb von Kommentaren und Zeichenketten ab AFrom; 0 ohne.</summary>
function FindWord(const AText, AWord: string; AFrom: Integer): Integer;
var
  mIndex, mNext: Integer;
begin
  mIndex := AFrom;
  while mIndex <= Length(AText) do
  begin
    mNext := SkipNoise(AText, mIndex);
    if mNext <> mIndex then
    begin
      mIndex := mNext;
      Continue;
    end;
    if SameText(Copy(AText, mIndex, Length(AWord)), AWord) and ((mIndex = 1) or
      not CharInSet(AText[mIndex - 1], cIdentChars)) and ((mIndex + Length(AWord) > Length(AText)) or
      not CharInSet(AText[mIndex + Length(AWord)], cIdentChars)) then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
  Result := 0;
end;

/// <summary>Position des ";" ab AFrom außerhalb von Kommentaren und Zeichenketten; 0 ohne.</summary>
function FindSemicolon(const AText: string; AFrom: Integer): Integer;
var
  mIndex, mNext: Integer;
begin
  mIndex := AFrom;
  while mIndex <= Length(AText) do
  begin
    mNext := SkipNoise(AText, mIndex);
    if mNext <> mIndex then
    begin
      mIndex := mNext;
      Continue;
    end;
    if AText[mIndex] = ';' then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
  Result := 0;
end;

/// <summary>Bezeichner, der vor AIndex (über Leerraum hinweg) endet.</summary>
function IdentBefore(const AText: string; AIndex: Integer): string;
var
  mEnd, mStart: Integer;
begin
  mEnd := AIndex - 1;
  while (mEnd > 0) and CharInSet(AText[mEnd], [' ', #9, #13, #10]) do
  begin
    Dec(mEnd);
  end;
  mStart := mEnd;
  while (mStart > 0) and CharInSet(AText[mStart], cIdentChars) do
  begin
    Dec(mStart);
  end;
  Result := Copy(AText, mStart + 1, mEnd - mStart);
end;

/// <summary>Ersetzt in der uses-Klausel ab AFrom bis AStop die Pfade hinter „in“; ATarget für die mutierte Unit
/// von ASource. AFound sagt, ob sie vorkam.</summary>
function RewriteUses(const AText: string; AFrom, AStop: Integer; const ASource: TAtlasMutationShadowSource;
  const ATarget: string; out AFound: Boolean): string;
var
  mIndex, mIn, mOpen, mClose: Integer;
  mPath, mBase: string;
begin
  mBase := TAtlasMutationShadows.FolderOf(ASource.ProjectFile);
  AFound := False;
  Result := Copy(AText, 1, AFrom - 1);
  mIndex := AFrom;
  while mIndex < AStop do
  begin
    mIn := FindWord(AText, 'in', mIndex);
    if (mIn = 0) or (mIn >= AStop) then
    begin
      Break;
    end;
    mClose := mIn + 2;
    while (mClose <= Length(AText)) and CharInSet(AText[mClose], [' ', #9, #13, #10]) do
    begin
      Inc(mClose);
    end;
    if (mClose > Length(AText)) or (AText[mClose] <> '''') then
    begin
      Result := Result + Copy(AText, mIndex, mIn + 2 - mIndex);
      mIndex := mIn + 2;
      Continue;
    end;
    mOpen := mClose;
    mClose := PosEx('''', AText, mOpen + 1);
    mPath := Copy(AText, mOpen + 1, mClose - mOpen - 1);
    if SameText(IdentBefore(AText, mIn), ASource.UnitName) then
    begin
      AFound := True;
      mPath := ATarget;
    end
    else
    begin
      mPath := TAtlasMutationShadows.Absolute(mBase, mPath);
    end;
    Result := Result + Copy(AText, mIndex, mOpen - mIndex) + Quoted(mPath);
    mIndex := mClose + 1;
  end;
  Result := Result + Copy(AText, mIndex, MaxInt);
end;

/// <summary>Position der nächsten Direktive {$R, {$RESOURCE, {$I oder {$INCLUDE mit Argument in AUpper (Text in
/// Großbuchstaben) ab AFrom; 0 ohne. AName ist ihr Anfang samt Leerzeichen.</summary>
function NextDirective(const AUpper: string; AFrom: Integer; out AName: string): Integer;
const
  cNames: array[0..3] of string = ('{$R ', '{$RESOURCE ', '{$I ', '{$INCLUDE ');
var
  mCandidate: string;
  mFound: Integer;
begin
  Result := 0;
  AName := '';
  for mCandidate in cNames do
  begin
    mFound := PosEx(mCandidate, AUpper, AFrom);
    if (mFound > 0) and ((Result = 0) or (mFound < Result)) then
    begin
      Result := mFound;
      AName := mCandidate;
    end;
  end;
end;

/// <summary>Neuer Text der Direktive ADirective (Anfang AName); {$R *.res} zeigt auf AResFile oder fällt weg,
/// Masken und Argumente mit Leerzeichen ohne Anführungszeichen bleiben.</summary>
function DirectiveText(const ADirective, AName, ABase, AResFile: string): string;
var
  mArgument, mPath: string;
begin
  mArgument := Trim(Copy(ADirective, Length(AName) + 1, Length(ADirective) - Length(AName) - 1));
  mPath := mArgument;
  if StartsStr('''', mPath) then
  begin
    mPath := Copy(mPath, 2, Length(mPath) - 2);
  end;
  if SameText(mPath, '*.res') then
  begin
    Result := '';
    if AResFile <> '' then
    begin
      Result := '{$R ' + Quoted(AResFile) + '}';
    end;
  end
  else if (mPath = '') or StartsStr('*', mPath) or ((Pos(' ', mPath) > 0) and not StartsStr('''', mArgument)) then
  begin
    Result := ADirective;
  end
  else
  begin
    Result := Copy(ADirective, 1, Length(AName)) + Quoted(TAtlasMutationShadows.Absolute(ABase, mPath)) + '}';
  end;
end;

/// <summary>{$R …}, {$RESOURCE …}, {$I …}, {$INCLUDE …} mit absolutem Pfad; {$R *.res} auf AResFile bzw. weg.
/// Schalter wie {$R+} oder {$I-} bleiben.</summary>
function RewriteDirectives(const AText, ABase, AResFile: string): string;
var
  mIndex, mStart, mClose: Integer;
  mName, mUpper: string;
begin
  Result := '';
  mIndex := 1;
  mUpper := UpperCase(AText);
  while True do
  begin
    mStart := NextDirective(mUpper, mIndex, mName);
    mClose := 0;
    if mStart > 0 then
    begin
      mClose := PosEx('}', AText, mStart);
    end;
    if mClose = 0 then
    begin
      Break;
    end;
    Result := Result + Copy(AText, mIndex, mStart - mIndex) +
      DirectiveText(Copy(AText, mStart, mClose - mStart + 1), mName, ABase, AResFile);
    mIndex := mClose + 1;
  end;
  Result := Result + Copy(AText, mIndex, MaxInt);
end;

/// <summary>dpr des Schattenprojekts; False ohne Programmkopf.</summary>
function ShadowDpr(const ASource: TAtlasMutationShadowSource; const AName, ATarget: string;
  out ADpr: string): Boolean;
var
  mBase, mResFile, mText: string;
  mProgram, mHeaderEnd, mUses, mUsesEnd: Integer;
  mFound: Boolean;
begin
  ADpr := '';
  mBase := TAtlasMutationShadows.FolderOf(ASource.ProjectFile);
  mText := ASource.Dpr;
  mProgram := FindWord(mText, 'program', 1);
  mHeaderEnd := 0;
  if mProgram > 0 then
  begin
    mHeaderEnd := FindSemicolon(mText, mProgram);
  end;
  if mHeaderEnd = 0 then
  begin
    Exit(False);
  end;
  mText := Copy(mText, 1, mProgram - 1) + 'program ' + AName + Copy(mText, mHeaderEnd, MaxInt);
  mHeaderEnd := FindSemicolon(mText, mProgram);
  mUses := FindWord(mText, 'uses', mHeaderEnd);
  if mUses > 0 then
  begin
    mUsesEnd := FindSemicolon(mText, mUses);
    mText := RewriteUses(mText, mUses, mUsesEnd, ASource, ATarget, mFound);
    if not mFound then
    begin
      // Nach dem Umschreiben hat sich die Länge geändert: Ende der Klausel neu suchen.
      mUsesEnd := FindSemicolon(mText, mUses);
      mText := Copy(mText, 1, mUsesEnd - 1) + ',' + cBreak + '  ' + ASource.UnitName + ' in ' + Quoted(ATarget) +
        Copy(mText, mUsesEnd, MaxInt);
    end;
  end
  else
  begin
    mText := Copy(mText, 1, mHeaderEnd) + cBreak + cBreak + 'uses' + cBreak + '  ' + ASource.UnitName + ' in ' +
      Quoted(ATarget) + ';' + Copy(mText, mHeaderEnd + 1, MaxInt);
  end;
  mResFile := '';
  if ASource.ResExists then
  begin
    mResFile := Copy(ASource.ProjectFile, 1, Length(ASource.ProjectFile) -
      Length(ExtractFileExt(ASource.ProjectFile))) + '.res';
  end;
  ADpr := RewriteDirectives(mText, mBase, mResFile);
  Result := True;
end;

{ dproj }

/// <summary>Ersetzt den Inhalt jedes Elements ATag durch AFunc(Inhalt).</summary>
function MapElements(const AText, ATag: string; const AFunc: TValueFunc): string;
var
  mIndex, mOpen, mStart, mClose: Integer;
  mAfter: Char;
begin
  Result := '';
  mIndex := 1;
  while True do
  begin
    mOpen := PosEx('<' + ATag, AText, mIndex);
    if mOpen = 0 then
    begin
      Break;
    end;
    mAfter := #0;
    if mOpen + Length(ATag) + 1 <= Length(AText) then
    begin
      mAfter := AText[mOpen + Length(ATag) + 1];
    end;
    mStart := PosEx('>', AText, mOpen);
    if not CharInSet(mAfter, ['>', ' ']) or (mStart = 0) or (AText[mStart - 1] = '/') then
    begin
      Result := Result + Copy(AText, mIndex, mOpen + 1 - mIndex);
      mIndex := mOpen + 1;
      Continue;
    end;
    mClose := PosEx('</' + ATag + '>', AText, mStart);
    if mClose = 0 then
    begin
      Break;
    end;
    Result := Result + Copy(AText, mIndex, mStart + 1 - mIndex) + AFunc(Copy(AText, mStart + 1, mClose - mStart - 1));
    mIndex := mClose;
  end;
  Result := Result + Copy(AText, mIndex, MaxInt);
end;

/// <summary>Ersetzt den Wert jedes Attributs Include= der Einträge ATag durch AFunc(Wert).</summary>
function MapIncludes(const AText, ATag: string; const AFunc: TValueFunc): string;
var
  mIndex, mOpen, mStart, mClose: Integer;
  mMarker: string;
begin
  Result := '';
  mIndex := 1;
  mMarker := '<' + ATag + ' Include="';
  while True do
  begin
    mOpen := PosEx(mMarker, AText, mIndex);
    if mOpen = 0 then
    begin
      Break;
    end;
    mStart := mOpen + Length(mMarker);
    mClose := PosEx('"', AText, mStart);
    if mClose = 0 then
    begin
      Break;
    end;
    Result := Result + Copy(AText, mIndex, mStart - mIndex) + AFunc(Copy(AText, mStart, mClose - mStart));
    mIndex := mClose;
  end;
  Result := Result + Copy(AText, mIndex, MaxInt);
end;

/// <summary>Liste von Pfaden mit absoluten Einträgen.</summary>
function AbsoluteList(const AList, ABase: string): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mParts := AList.Split([';']);
  for mIndex := 0 to High(mParts) do
  begin
    mParts[mIndex] := TAtlasMutationShadows.Absolute(ABase, mParts[mIndex]);
  end;
  Result := string.Join(';', mParts);
end;

/// <summary>dproj mit Ordnern des Originals vorn im Such- und Include-Pfad der Basis-Konfiguration.</summary>
function WithFolders(const AText, AFolders: string): string;
var
  mGroup, mItems: Integer;
  mLines: string;
begin
  mLines := cBreak + '        <DCC_UnitSearchPath>' + AFolders + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    cBreak + '        <DCC_IncludePath>' + AFolders + ';$(DCC_IncludePath)</DCC_IncludePath>';
  mGroup := Pos(cBaseGroup, AText);
  if mGroup > 0 then
  begin
    mGroup := mGroup + Length(cBaseGroup);
    Exit(Copy(AText, 1, mGroup - 1) + mLines + Copy(AText, mGroup, MaxInt));
  end;
  // Ohne Basis-Gruppe: eigene vor die erste ItemGroup.
  mItems := Pos('<ItemGroup>', AText);
  if mItems = 0 then
  begin
    mItems := Pos('</Project>', AText);
  end;
  if mItems = 0 then
  begin
    Exit(AText);
  end;
  Result := Copy(AText, 1, mItems - 1) + cBaseGroup + mLines + cBreak + '    </PropertyGroup>' + cBreak + '    ' +
    Copy(AText, mItems, MaxInt);
end;

/// <summary>Setzt den Inhalt aller Elemente ATags auf AValue.</summary>
function SetElements(const AText: string; const ATags: array of string; const AValue: string): string;
var
  mTag, mValue: string;
begin
  mValue := AValue;
  Result := AText;
  for mTag in ATags do
  begin
    Result := MapElements(Result, mTag,
      function(const AOld: string): string
      begin
        Result := mValue;
      end);
  end;
end;

/// <summary>MainSource, Projektname und GUID des Schattenprojekts.</summary>
function DprojIdentity(const ASource: TAtlasMutationShadowSource; const AName, ADprName: string): string;
var
  mDprName: string;
begin
  mDprName := ADprName;
  Result := MapElements(ASource.Dproj, 'MainSource',
    function(const AValue: string): string
    begin
      // <MainSource>MainSource</MainSource> in DelphiCompile ist eine Kennung, kein Dateiname.
      Result := AValue;
      if EndsText('.dpr', Trim(AValue)) then
      begin
        Result := mDprName;
      end;
    end);
  Result := StringReplace(Result, '<Source Name="MainSource">' + BaseNameOf(ASource.ProjectFile) + '.dpr</Source>',
    '<Source Name="MainSource">' + ADprName + '</Source>', [rfIgnoreCase]);
  Result := SetElements(Result, ['ProjectName'], AName);
  Result := SetElements(Result, ['SanitizedProjectName'], StringReplace(AName, '.', '_', [rfReplaceAll]));
  Result := SetElements(Result, ['ProjectGuid'], ASource.Guid);
end;

/// <summary>Pfade absolut, Ausgaben nach Out, Ereignisse leer, mutierte Unit nach ATarget.</summary>
function DprojPaths(const AText: string; const ASource: TAtlasMutationShadowSource; const ATarget: string): string;
var
  mBase, mUnitFile, mTarget, mTag: string;
begin
  mBase := XmlEscaped(TAtlasMutationShadows.FolderOf(ASource.ProjectFile));
  mUnitFile := XmlEscaped(TAtlasMutationShadows.Normalized(ASource.UnitFile));
  mTarget := XmlEscaped(ATarget);
  Result := AText;
  for mTag in cPathLists do
  begin
    Result := MapElements(Result, mTag,
      function(const AValue: string): string
      begin
        Result := AbsoluteList(AValue, mBase);
      end);
  end;
  for mTag in cPathSingles do
  begin
    Result := MapElements(Result, mTag,
      function(const AValue: string): string
      begin
        Result := TAtlasMutationShadows.Absolute(mBase, AValue);
      end);
  end;
  Result := SetElements(Result, ['DCC_ExeOutput'], TAtlasMutationShadows.cOutFolder);
  Result := SetElements(Result, cOutputs, TAtlasMutationShadows.cDcuFolder);
  Result := SetElements(Result, cEvents, '');
  for mTag in cIncludeItems do
  begin
    Result := MapIncludes(Result, mTag,
      function(const AValue: string): string
      begin
        Result := TAtlasMutationShadows.Absolute(mBase, AValue);
        if SameText(Result, mUnitFile) then
        begin
          Result := mTarget;
        end;
      end);
  end;
  Result := WithFolders(Result, mBase + ';' + XmlEscaped(TAtlasMutationShadows.FolderOf(ASource.UnitFile)));
end;

function ShadowDproj(const ASource: TAtlasMutationShadowSource; const AName, ADprName, ATarget: string): string;
begin
  Result := DprojPaths(DprojIdentity(ASource, AName, ADprName), ASource, ATarget);
end;

class function TAtlasMutationShadows.Build(const ASource: TAtlasMutationShadowSource;
  out AShadow: TAtlasMutationShadow): Boolean;
var
  mProject, mTarget: string;
begin
  AShadow := Default(TAtlasMutationShadow);
  mProject := BaseNameOf(ASource.ProjectFile);
  AShadow.Name := mProject + cSuffix;
  AShadow.Folder := DataFolderOf(ASource.ProjectFile) + '\' + mProject;
  AShadow.DprFile := AShadow.Folder + '\' + AShadow.Name + '.dpr';
  AShadow.DprojFile := AShadow.Folder + '\' + AShadow.Name + '.dproj';
  mTarget := cSourceFolder + '\' + FileNameOf(ASource.UnitFile);
  AShadow.UnitFile := AShadow.Folder + '\' + mTarget;
  Result := ShadowDpr(ASource, AShadow.Name, mTarget, AShadow.Dpr);
  if Result then
  begin
    AShadow.Dproj := ShadowDproj(ASource, AShadow.Name, AShadow.Name + '.dpr', mTarget);
  end
  else
  begin
    AShadow := Default(TAtlasMutationShadow);
  end;
end;

end.
