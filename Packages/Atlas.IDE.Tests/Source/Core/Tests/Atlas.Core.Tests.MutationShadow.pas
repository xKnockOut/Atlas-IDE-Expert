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
// dpr: Programmname ersetzt; alle „in '…'“-Pfade und die Argumente von
// {$R}/{$I} absolut zum Ordner des Originals ({$R 'X.res' 'X.rc'} mit beiden),
// die mutierte Unit nach Src\ (mit oder ohne „in“ in der dpr; fehlt sie, wird
// sie an die uses-Klausel angehängt); {$R *.res} zeigt auf die .res des
// Originals oder fällt weg, wenn es keine gibt. Eine Form, die das Umschreiben
// nicht kennt, meldet Build als Problem samt Textstelle, statt eine dpr zu
// liefern, die erst beim Bauen scheitert.
// dproj: MainSource, Projektname und GUID neu; relative Pfade (Suchpfade,
// Include= der Einträge, Symbol, Manifest) absolut; der Ordner des Originals
// und der der Unit stehen vorn im Such- und Include-Pfad (die Kopie liegt
// woanders, die Nachbarn sollen sich weiter finden); Ausgaben nach Out\,
// auch wenn das Original keine nennt (sonst legte der Compiler die DCUs neben
// die Quelltexte des Originals); Ereignisse vor und nach dem Bauen geleert,
// weil sie Dateien des Originals überschreiben könnten.
// Das Original bleibt unverändert, weil zwei Bedingungen zusammen gelten:
// Der Lauf schreibt nur in den Ordner des Schattenprojekts (IsShadowFile vor
// jedem Schreiben), und keine Datei des Originals liegt in diesem Ordner
// (Separate vor dem Anlegen). Wer eine Unit aus dem Schattenprojekt selbst
// mutieren will, wird abgewiesen.
// Pfade sind Windows-Pfade; die Funktionen arbeiten nur auf Zeichenketten.

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Warum Build kein Schattenprojekt liefert.</summary>
  TAtlasMutationShadowProblem = (
    /// <summary>Kein Problem.</summary>
    None,
    /// <summary>Die dpr hat keinen Programmkopf.</summary>
    NoProgram,
    /// <summary>Eine Direktive {$R}/{$I} hat eine unbekannte Form (zu viele Argumente, offenes Anführungszeichen).
    /// </summary>
    Directive,
    /// <summary>Ein Eintrag der uses-Klausel hat eine unbekannte Form.</summary>
    UsesEntry);
  {$SCOPEDENUMS OFF}

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
    /// <summary>Warum Build scheiterte, sonst None.</summary>
    Problem: TAtlasMutationShadowProblem;
    /// <summary>Textstelle der dpr, an der das Umschreiben scheiterte (Direktive oder uses-Eintrag).</summary>
    ProblemText: string;
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
    /// <summary>Schattenprojekt zu ASource. False, wenn sich die dpr nicht umschreiben lässt; AShadow ist dann leer
    /// bis auf Problem und ProblemText.</summary>
    class function Build(const ASource: TAtlasMutationShadowSource; out AShadow: TAtlasMutationShadow): Boolean;
      static;
    /// <summary>Formulardateien, die mit der Unit AUnitFile kopiert werden müssen, falls es sie gibt.</summary>
    class function CompanionFiles(const AUnitFile: string): TArray<string>; static;
    /// <summary>Dateien des Originals, die der Lauf liest und nie schreiben darf: Unit, ihre Formulardateien, dproj,
    /// dpr und res des Testprojekts.</summary>
    class function OriginalFiles(const ASource: TAtlasMutationShadowSource): TArray<string>; static;
    /// <summary>Liegt AFileName in AFolder oder darunter? Pfade normalisiert, ohne Rücksicht auf
    /// Groß-/Kleinschreibung (Windows).</summary>
    class function Inside(const AFolder, AFileName: string): Boolean; static;
    /// <summary>Darf der Lauf AFileName schreiben? Nur Dateien im Ordner von AShadow.</summary>
    class function IsShadowFile(const AShadow: TAtlasMutationShadow; const AFileName: string): Boolean; static;
    /// <summary>Sind Schattenprojekt und Original getrennt? dpr, dproj und Kopie der Unit liegen im Ordner von
    /// AShadow, und keine Datei des Originals (OriginalFiles) liegt dort. Sonst darf der Lauf nicht beginnen.</summary>
    class function Separate(const ASource: TAtlasMutationShadowSource; const AShadow: TAtlasMutationShadow): Boolean;
      static;
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
  System.StrUtils,
  System.Math,
  Atlas.Text.Chars;

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
  cBlanks = [' ', #9, #13, #10];

type
  TValueFunc = reference to function(const AValue: string): string;

  /// <summary>Was das Umschreiben der uses-Klausel braucht und ob es die mutierte Unit fand.</summary>
  TUsesRewrite = record
    /// <summary>Name der mutierten Unit.</summary>
    UnitName: string;
    /// <summary>Pfad der Kopie, relativ zum Schattenprojekt.</summary>
    Target: string;
    /// <summary>Ordner des Originals, Bezug für relative Pfade.</summary>
    Base: string;
    /// <summary>Kam die mutierte Unit vor?</summary>
    Found: Boolean;
  end;

{ Pfade }

{ TAtlasMutationShadows }

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

/// <summary>AFileName mit der Endung AExt statt der eigenen.</summary>
function WithExtension(const AFileName, AExt: string): string;
begin
  Result := Copy(AFileName, 1, Length(AFileName) - Length(ExtractFileExt(AFileName))) + AExt;
end;

class function TAtlasMutationShadows.OriginalFiles(const ASource: TAtlasMutationShadowSource): TArray<string>;
begin
  Result := TArray<string>.Create(ASource.UnitFile, ASource.ProjectFile, WithExtension(ASource.ProjectFile, '.dpr'),
    WithExtension(ASource.ProjectFile, '.res')) + CompanionFiles(ASource.UnitFile);
end;

class function TAtlasMutationShadows.Inside(const AFolder, AFileName: string): Boolean;
var
  mFolder: string;
begin
  mFolder := Normalized(AFolder);
  // Mit Trenner vergleichen: C:\P\AB liegt nicht in C:\P\A.
  Result := (mFolder <> '') and (Trim(AFileName) <> '') and StartsText(mFolder + '\', Normalized(AFileName) + '\');
end;

class function TAtlasMutationShadows.IsShadowFile(const AShadow: TAtlasMutationShadow;
  const AFileName: string): Boolean;
begin
  Result := Inside(AShadow.Folder, AFileName);
end;

class function TAtlasMutationShadows.Separate(const ASource: TAtlasMutationShadowSource;
  const AShadow: TAtlasMutationShadow): Boolean;
var
  mOriginal: string;
begin
  Result := IsShadowFile(AShadow, AShadow.DprFile) and IsShadowFile(AShadow, AShadow.DprojFile) and
    IsShadowFile(AShadow, AShadow.UnitFile);
  if not Result then
  begin
    Exit;
  end;
  for mOriginal in OriginalFiles(ASource) do
  begin
    if IsShadowFile(AShadow, mOriginal) then
    begin
      Exit(False);
    end;
  end;
end;

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

function XmlEscaped(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
end;

function Quoted(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''''', [rfReplaceAll]) + '''';
end;

{ dpr }

/// <summary>Zeichen eines (auch gepunkteten) Bezeichners; Delphi erlaubt Unicode.</summary>
function IsNameChar(AChar: Char): Boolean;
begin
  Result := TTextChars.IsIdentChar(AChar) or (AChar = '.');
end;

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
      not IsNameChar(AText[mIndex - 1])) and ((mIndex + Length(AWord) > Length(AText)) or
      not IsNameChar(AText[mIndex + Length(AWord)])) then
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

/// <summary>Position hinter Leerraum und Kommentaren ab AIndex, höchstens AStop. Zeichenketten sind kein Leerraum.
/// </summary>
function SkipBlank(const AText: string; AIndex, AStop: Integer): Integer;
var
  mNext: Integer;
begin
  Result := AIndex;
  while Result < AStop do
  begin
    if CharInSet(AText[Result], cBlanks) then
    begin
      Inc(Result);
      Continue;
    end;
    if AText[Result] = '''' then
    begin
      Break;
    end;
    mNext := SkipNoise(AText, Result);
    if mNext <= Result then
    begin
      Break;
    end;
    Result := mNext;
  end;
  Result := Min(Result, AStop);
end;

/// <summary>Position des Kommas hinter dem uses-Eintrag ab AFrom außerhalb von Kommentaren und Zeichenketten;
/// AStop ohne.</summary>
function EntryEnd(const AText: string; AFrom, AStop: Integer): Integer;
var
  mNext: Integer;
begin
  Result := AFrom;
  while (Result < AStop) and (AText[Result] <> ',') do
  begin
    mNext := SkipNoise(AText, Result);
    if mNext > Result then
    begin
      Result := mNext;
    end
    else
    begin
      Inc(Result);
    end;
  end;
  Result := Min(Result, AStop);
end;

/// <summary>Position des schließenden Anführungszeichens zu dem bei AOpen ('' zählt als Zeichen); 0 ohne.</summary>
function QuoteEnd(const AText: string; AOpen: Integer): Integer;
begin
  Result := PosEx('''', AText, AOpen + 1);
  while (Result > 0) and (Result < Length(AText)) and (AText[Result + 1] = '''') do
  begin
    Result := PosEx('''', AText, Result + 2);
  end;
end;

/// <summary>Steht das Wort AWord bei AIndex (vor AStop) und endet dort?</summary>
function IsWordAt(const AText, AWord: string; AIndex, AStop: Integer): Boolean;
var
  mAfter: Integer;
begin
  mAfter := AIndex + Length(AWord);
  Result := (mAfter <= AStop) and SameText(Copy(AText, AIndex, Length(AWord)), AWord) and
    ((mAfter > Length(AText)) or not IsNameChar(AText[mAfter]));
end;

/// <summary>Ein uses-Eintrag „Name“ oder „Name in 'Pfad'“ (mit Kommentaren) von AFrom bis vor AStop: Pfad absolut
/// zu ARewrite.Base, die mutierte Unit mit „in ARewrite.Target“, ob mit „in“ oder ohne. False bei unbekannter Form.
/// </summary>
function RewriteEntry(const AText: string; AFrom, AStop: Integer; var ARewrite: TUsesRewrite;
  out AEntry: string): Boolean;
var
  mName, mNameEnd, mIn, mOpen, mClose, mRest: Integer;
  mMine: Boolean;
  mPath: string;
begin
  AEntry := Copy(AText, AFrom, AStop - AFrom);
  mName := SkipBlank(AText, AFrom, AStop);
  mNameEnd := mName;
  while (mNameEnd < AStop) and IsNameChar(AText[mNameEnd]) do
  begin
    Inc(mNameEnd);
  end;
  if mNameEnd = mName then
  begin
    // Nur Leerraum und Kommentare: nichts umzuschreiben.
    Exit(mName >= AStop);
  end;
  mMine := SameText(Copy(AText, mName, mNameEnd - mName), ARewrite.UnitName);
  mIn := SkipBlank(AText, mNameEnd, AStop);
  mRest := mNameEnd;
  if IsWordAt(AText, 'in', mIn, AStop) then
  begin
    mOpen := SkipBlank(AText, mIn + 2, AStop);
    mClose := 0;
    if (mOpen < AStop) and (AText[mOpen] = '''') then
    begin
      mClose := QuoteEnd(AText, mOpen);
    end;
    if (mClose = 0) or (mClose >= AStop) then
    begin
      Exit(False);
    end;
    mPath := ARewrite.Target;
    if not mMine then
    begin
      mPath := TAtlasMutationShadows.Absolute(ARewrite.Base,
        StringReplace(Copy(AText, mOpen + 1, mClose - mOpen - 1), '''''', '''', [rfReplaceAll]));
    end;
    AEntry := Copy(AText, AFrom, mOpen - AFrom) + Quoted(mPath);
    mRest := mClose + 1;
  end
  else
  begin
    AEntry := Copy(AText, AFrom, mNameEnd - AFrom);
    if mMine then
    begin
      AEntry := AEntry + ' in ' + Quoted(ARewrite.Target);
    end;
  end;
  // Hinter Name bzw. Pfad dürfen nur Leerraum und Kommentare ({Form1}) stehen.
  Result := SkipBlank(AText, mRest, AStop) >= AStop;
  AEntry := AEntry + Copy(AText, mRest, AStop - mRest);
  ARewrite.Found := ARewrite.Found or mMine;
end;

/// <summary>Schreibt die uses-Klausel (AFrom zeigt auf „uses“, AStop auf ihr Semikolon) Eintrag für Eintrag um; siehe
/// RewriteEntry. ARewrite.Found sagt, ob die mutierte Unit vorkam; AProblem ist der erste Eintrag unbekannter Form,
/// sonst leer.</summary>
function RewriteUses(const AText: string; AFrom, AStop: Integer; var ARewrite: TUsesRewrite;
  out AProblem: string): string;
var
  mIndex, mEnd: Integer;
  mEntry: string;
begin
  AProblem := '';
  mIndex := AFrom + Length('uses');
  Result := Copy(AText, 1, mIndex - 1);
  while mIndex < AStop do
  begin
    mEnd := EntryEnd(AText, mIndex, AStop);
    if not RewriteEntry(AText, mIndex, mEnd, ARewrite, mEntry) then
    begin
      AProblem := Trim(Copy(AText, mIndex, mEnd - mIndex));
      Exit(AText);
    end;
    Result := Result + mEntry;
    if mEnd < AStop then
    begin
      Result := Result + ',';
    end;
    mIndex := mEnd + 1;
  end;
  Result := Result + Copy(AText, AStop, MaxInt);
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

/// <summary>Argumente einer Direktive: in Anführungszeichen ('' als Zeichen) oder bis zum Leerraum. False bei offenem
/// Anführungszeichen.</summary>
function DirectiveArguments(const AText: string; out AArguments: TArray<string>): Boolean;
var
  mIndex, mClose: Integer;
begin
  AArguments := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], cBlanks) then
    begin
      Inc(mIndex);
      Continue;
    end;
    if AText[mIndex] = '''' then
    begin
      mClose := QuoteEnd(AText, mIndex);
      if mClose = 0 then
      begin
        Exit(False);
      end;
      AArguments := AArguments + [StringReplace(Copy(AText, mIndex + 1, mClose - mIndex - 1), '''''', '''',
        [rfReplaceAll])];
      mIndex := mClose + 1;
      Continue;
    end;
    mClose := mIndex;
    while (mClose <= Length(AText)) and not CharInSet(AText[mClose], cBlanks) do
    begin
      Inc(mClose);
    end;
    AArguments := AArguments + [Copy(AText, mIndex, mClose - mIndex)];
    mIndex := mClose;
  end;
  Result := True;
end;

/// <summary>Ist AName (Anfang aus NextDirective) {$I bzw. {$INCLUDE?</summary>
function IsIncludeDirective(const AName: string): Boolean;
begin
  Result := SameText(AName, '{$I ') or SameText(AName, '{$INCLUDE ');
end;

/// <summary>Argumente AArguments absolut zu ABase, mit Anführungszeichen und durch Leerzeichen getrennt; Masken (*)
/// bleiben.</summary>
function AbsoluteArguments(const AArguments: TArray<string>; const ABase: string): string;
var
  mArgument: string;
begin
  Result := '';
  for mArgument in AArguments do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    if StartsStr('*', mArgument) then
    begin
      Result := Result + mArgument;
    end
    else
    begin
      Result := Result + Quoted(TAtlasMutationShadows.Absolute(ABase, mArgument));
    end;
  end;
end;

/// <summary>Neuer Text ATextOut der Direktive ADirective (Anfang AName): jedes Argument absolut ({$R} hat bis zu zwei:
/// .res und .rc, {$I} eins); {$R *.res} zeigt auf AResFile oder fällt weg; Masken und ein {$I} ohne
/// Anführungszeichen mit Leerzeichen bleiben. False bei unbekannter Form (mehr Argumente, offenes Anführungszeichen).
/// </summary>
function DirectiveText(const ADirective, AName, ABase, AResFile: string; out ATextOut: string): Boolean;
var
  mArgument: string;
  mArguments: TArray<string>;
  mMax: Integer;
begin
  ATextOut := ADirective;
  mArgument := Trim(Copy(ADirective, Length(AName) + 1, Length(ADirective) - Length(AName) - 1));
  Result := DirectiveArguments(mArgument, mArguments);
  if not Result or (mArguments = nil) then
  begin
    Exit;
  end;
  if (Length(mArguments) = 1) and SameText(mArguments[0], '*.res') then
  begin
    ATextOut := '';
    if AResFile <> '' then
    begin
      ATextOut := '{$R ' + Quoted(AResFile) + '}';
    end;
    Exit;
  end;
  mMax := 2;
  if IsIncludeDirective(AName) then
  begin
    // Ein Pfad ohne Anführungszeichen mit Leerzeichen bleibt, der Include-Pfad findet ihn im Ordner des Originals.
    if (Length(mArguments) > 1) and not StartsStr('''', mArgument) then
    begin
      Exit;
    end;
    mMax := 1;
  end;
  Result := Length(mArguments) <= mMax;
  if Result then
  begin
    ATextOut := Copy(ADirective, 1, Length(AName)) + AbsoluteArguments(mArguments, ABase) + '}';
  end;
end;

/// <summary>{$R …}, {$RESOURCE …}, {$I …}, {$INCLUDE …} mit absoluten Pfaden; {$R *.res} auf AResFile bzw. weg.
/// Schalter wie {$R+} oder {$I-} bleiben. AProblem ist die erste Direktive unbekannter Form, sonst leer.</summary>
function RewriteDirectives(const AText, ABase, AResFile: string; out AProblem: string): string;
var
  mIndex, mStart, mClose: Integer;
  mName, mUpper, mDirective, mNew: string;
begin
  Result := '';
  AProblem := '';
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
    mDirective := Copy(AText, mStart, mClose - mStart + 1);
    if not DirectiveText(mDirective, mName, ABase, AResFile, mNew) then
    begin
      AProblem := mDirective;
      Exit(AText);
    end;
    Result := Result + Copy(AText, mIndex, mStart - mIndex) + mNew;
    mIndex := mClose + 1;
  end;
  Result := Result + Copy(AText, mIndex, MaxInt);
end;

/// <summary>Datei der .res des Originals, leer ohne.</summary>
function ResFileOf(const ASource: TAtlasMutationShadowSource): string;
begin
  Result := '';
  if ASource.ResExists then
  begin
    Result := WithExtension(ASource.ProjectFile, '.res');
  end;
end;

/// <summary>Schreibt die uses-Klausel ab AHeaderEnd (Semikolon des Programmkopfs) um bzw. legt eine an.</summary>
function WithShadowUses(const AText: string; AHeaderEnd: Integer; const ASource: TAtlasMutationShadowSource;
  const ATarget: string; out AProblem: string): string;
var
  mUses, mUsesEnd: Integer;
  mRewrite: TUsesRewrite;
begin
  AProblem := '';
  mUses := FindWord(AText, 'uses', AHeaderEnd);
  if mUses = 0 then
  begin
    Exit(Copy(AText, 1, AHeaderEnd) + cBreak + cBreak + 'uses' + cBreak + '  ' + ASource.UnitName + ' in ' +
      Quoted(ATarget) + ';' + Copy(AText, AHeaderEnd + 1, MaxInt));
  end;
  mUsesEnd := FindSemicolon(AText, mUses);
  mRewrite := Default(TUsesRewrite);
  mRewrite.UnitName := ASource.UnitName;
  mRewrite.Target := ATarget;
  mRewrite.Base := TAtlasMutationShadows.FolderOf(ASource.ProjectFile);
  Result := RewriteUses(AText, mUses, mUsesEnd, mRewrite, AProblem);
  if (AProblem = '') and not mRewrite.Found then
  begin
    // Nach dem Umschreiben hat sich die Länge geändert: Ende der Klausel neu suchen.
    mUsesEnd := FindSemicolon(Result, mUses);
    Result := Copy(Result, 1, mUsesEnd - 1) + ',' + cBreak + '  ' + ASource.UnitName + ' in ' + Quoted(ATarget) +
      Copy(Result, mUsesEnd, MaxInt);
  end;
end;

/// <summary>dpr des Schattenprojekts nach AShadow.Dpr; sonst AShadow.Problem und ProblemText.</summary>
procedure ShadowDpr(const ASource: TAtlasMutationShadowSource; const ATarget: string;
  var AShadow: TAtlasMutationShadow);
var
  mText, mProblem: string;
  mProgram, mHeaderEnd: Integer;
begin
  mText := ASource.Dpr;
  mProgram := FindWord(mText, 'program', 1);
  mHeaderEnd := 0;
  if mProgram > 0 then
  begin
    mHeaderEnd := FindSemicolon(mText, mProgram);
  end;
  if mHeaderEnd = 0 then
  begin
    AShadow.Problem := TAtlasMutationShadowProblem.NoProgram;
    Exit;
  end;
  mText := Copy(mText, 1, mProgram - 1) + 'program ' + AShadow.Name + Copy(mText, mHeaderEnd, MaxInt);
  mText := WithShadowUses(mText, FindSemicolon(mText, mProgram), ASource, ATarget, mProblem);
  if mProblem <> '' then
  begin
    AShadow.Problem := TAtlasMutationShadowProblem.UsesEntry;
    AShadow.ProblemText := mProblem;
    Exit;
  end;
  mText := RewriteDirectives(mText, TAtlasMutationShadows.FolderOf(ASource.ProjectFile), ResFileOf(ASource),
    mProblem);
  if mProblem <> '' then
  begin
    AShadow.Problem := TAtlasMutationShadowProblem.Directive;
    AShadow.ProblemText := mProblem;
    Exit;
  end;
  AShadow.Dpr := mText;
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

/// <summary>dproj mit Ordnern des Originals vorn im Such- und Include-Pfad der Basis-Konfiguration und den
/// Ausgaben nach Out.</summary>
function WithFolders(const AText, AFolders: string): string;
var
  mGroup, mItems: Integer;
  mLines: string;
begin
  // Ausgaben auch dann nach Out, wenn das Original keine nennt: Ohne DCC_DcuOutput legte der Compiler die DCUs neben
  // die Quelltexte des Originals.
  mLines := cBreak + '        <DCC_UnitSearchPath>' + AFolders + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    cBreak + '        <DCC_IncludePath>' + AFolders + ';$(DCC_IncludePath)</DCC_IncludePath>' + cBreak +
    '        <DCC_ExeOutput>' + TAtlasMutationShadows.cOutFolder + '</DCC_ExeOutput>' + cBreak +
    '        <DCC_DcuOutput>' + TAtlasMutationShadows.cDcuFolder + '</DCC_DcuOutput>';
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
  mProject, mTarget, mProblemText: string;
  mProblem: TAtlasMutationShadowProblem;
begin
  AShadow := Default(TAtlasMutationShadow);
  mProject := BaseNameOf(ASource.ProjectFile);
  AShadow.Name := mProject + cSuffix;
  AShadow.Folder := DataFolderOf(ASource.ProjectFile) + '\' + mProject;
  AShadow.DprFile := AShadow.Folder + '\' + AShadow.Name + '.dpr';
  AShadow.DprojFile := AShadow.Folder + '\' + AShadow.Name + '.dproj';
  mTarget := cSourceFolder + '\' + FileNameOf(ASource.UnitFile);
  AShadow.UnitFile := AShadow.Folder + '\' + mTarget;
  ShadowDpr(ASource, mTarget, AShadow);
  Result := AShadow.Problem = TAtlasMutationShadowProblem.None;
  if Result then
  begin
    AShadow.Dproj := ShadowDproj(ASource, AShadow.Name, AShadow.Name + '.dpr', mTarget);
    Exit;
  end;
  mProblem := AShadow.Problem;
  mProblemText := AShadow.ProblemText;
  AShadow := Default(TAtlasMutationShadow);
  AShadow.Problem := mProblem;
  AShadow.ProblemText := mProblemText;
end;

end.
