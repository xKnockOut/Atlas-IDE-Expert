unit Atlas.Common.Rules.Builtin.Files;

// Regeln für Dateipfade (#909, Gruppe Robustheit und Muster):
//   path-concat-without-delimiter  Ordner ohne abschließendes Trennzeichen
//                                  (ExtractFileDir, ExcludeTrailingPathDelimiter,
//                                  GetCurrentDir, TPath.GetDocumentsPath …) mit +
//                                  an einen Namen gehängt (#968). Der Ordner kommt
//                                  direkt aus dem Aufruf oder aus einer lokalen
//                                  Variablen, der die Routine nur solche Werte
//                                  zuweist. Ein Literal als Name meldet mit hoher,
//                                  ein Bezeichner mit mittlerer Konfidenz;
//                                  Trennzeichen, Endungen und Texte, die mit
//                                  Leerzeichen oder Satzzeichen beginnen, bleiben
//                                  still. Korrektur: TPath.Combine.
//   hardcoded-path                 String-Literal mit Laufwerksbuchstaben oder
//                                  UNC-Pfad, eigene Meldung für Benutzerordner
//                                  (#969). Laufwerkswurzeln wie 'C:\' und
//                                  Präfixe wie '\\?\' bleiben still, ebenso
//                                  Test-Units und Units aus allowUnits.
//   filename-compare-case          Dateinamen mit = bzw. <> verglichen (#970):
//                                  eine Seite aus ExtractFileName & Co., TPath,
//                                  Application.ExeName oder einem Namen auf
//                                  FileName, die andere kein Leertext und kein
//                                  Literal ohne Buchstaben. Still, wenn dieselbe
//                                  Anweisung dieselben Seiten auch ohne Groß-/
//                                  Kleinschreibung vergleicht (SameText & Co.,
//                                  plattformabhängig etwa mit PathDelim = '\'),
//                                  und in Test-Units (Testdoubles vergleichen
//                                  mit selbst vergebenen Namen). Korrektur:
//                                  SameFileName.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cPathConcatWithoutDelimiterRuleId = 'path-concat-without-delimiter';
  cHardcodedPathRuleId = 'hardcoded-path';
  cFilenameCompareCaseRuleId = 'filename-compare-case';

type
  TPathConcatWithoutDelimiterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Name der Funktion, wenn ANode einen Ordner ohne abschließendes Trennzeichen liefert
    /// (ExtractFileDir, TPath.GetDocumentsPath …); sonst ''.</summary>
    class function DirectorySource(ANode: TSyntaxNode): string; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Art eines festen Pfads; None, wenn der Text kein fester Pfad ist.</summary>
  THardcodedPathKind = (None, Drive, UserFolder, Network);
{$SCOPEDENUMS OFF}

  THardcodedPathRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Art des Pfads im Klartext APath: C:\…, C:\Users\…, \\server\….</summary>
    class function PathKind(const APath: string): THardcodedPathKind; static;
    /// <summary>Passt AUnitName auf einen Eintrag aus allowUnits (Groß-/Kleinschreibung egal, * am Ende als
    /// Präfix)?</summary>
    class function UnitAllowed(const AUnitName: string; const AAllowed: TArray<string>): Boolean; static;
  end;

  TFilenameCompareCaseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Liefert ANode einen Datei- oder Pfadnamen (ExtractFileName, TPath.GetFileName,
    /// Application.ExeName, X.FileName …)?</summary>
    class function IsFileNameExpression(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Vergleicht die Anweisung um ACompare dieselben Seiten auch ohne Groß-/Kleinschreibung
    /// (SameText, SameFileName, CompareText …)? Dann ist der genaue Vergleich gewollt, etwa nur außerhalb von
    /// Windows.</summary>
    class function ComparedIgnoringCase(const AText: string; ACompare: TSyntaxNode): Boolean; static;
  end;

/// <summary>Name und Qualifizierer eines Aufrufs oder Bezeichners: TPath.GetDocumentsPath ergibt
/// GetDocumentsPath und TPath; ohne Aufruf, Bezeichner oder Punktkette False.</summary>
function CalleeName(ANode: TSyntaxNode; out AName, AQualifier: string): Boolean;

procedure RegisterFileRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFilesText = (Folder, ConcatTitle, UseCombine, Returns, ComesFrom, NoBackslashLiteral, NoBackslash, PathTitle,
    FixedPath, UserPath, NetworkPath, CompareTitle, CaseInsensitive, UseSameFileName);

const
  cTexts: array[TFilesText] of TAtlasText = (
    (De: 'Ordner'; En: 'Folder'),
    (De: 'Pfad ohne Trennzeichen zusammengesetzt'; En: 'Path assembled without delimiter'),
    (De: 'TPath.Combine verwenden'; En: 'Use TPath.Combine'),
    (De: '%s liefert'; En: '%s returns'),
    (De: '%s kommt aus %s und hat'; En: '%s comes from %s and has'),
    (De: '%s keinen abschließenden Backslash; das Ergebnis ist …\%s%s.';
     En: '%s no trailing backslash; the result is …\%s%s.'),
    (De: '%s keinen abschließenden Backslash; %s wird ohne Trennzeichen angehängt.';
     En: '%s no trailing backslash; %s is appended without delimiter.'),
    (De: 'Fester Dateipfad im Code'; En: 'Fixed file path in code'),
    (De: 'Fester Dateipfad; auf anderen Rechnern fehlt er womöglich.';
     En: 'Fixed file path; it may be missing on other computers.'),
    (De: 'Fester Benutzerpfad; auf anderen Rechnern gibt es ihn nicht.';
     En: 'Fixed user path; it does not exist on other computers.'),
    (De: 'Fester Netzwerkpfad; auf anderen Rechnern und ohne Netzwerk fehlt er womöglich.';
     En: 'Fixed network path; it may be missing on other computers and without a network.'),
    (De: 'Dateinamen mit = verglichen'; En: 'File names compared with ='),
    (De: 'Dateinamen unterscheiden unter Windows nicht nach Groß-/Kleinschreibung; SameFileName vergleicht richtig.';
     En: 'File names on Windows do not distinguish upper and lower case; SameFileName compares correctly.'),
    (De: 'SameFileName verwenden'; En: 'Use SameFileName'));

{$SCOPEDENUMS OFF}

const
  // System.SysUtils: Ordner ohne abschließendes Trennzeichen.
  cSysUtilsDirectories: array[0..4] of string = ('ExtractFileDir', 'ExcludeTrailingPathDelimiter',
    'ExcludeTrailingBackslash', 'GetCurrentDir', 'GetHomePath');
  // System.IOUtils.TPath: Ordner ohne abschließendes Trennzeichen (GetTempPath hat eins).
  cPathDirectories: array[0..20] of string = ('GetDocumentsPath', 'GetSharedDocumentsPath', 'GetHomePath',
    'GetDirectoryName', 'GetLibraryPath', 'GetCachePath', 'GetPublicPath', 'GetPicturesPath',
    'GetSharedPicturesPath', 'GetCameraPath', 'GetSharedCameraPath', 'GetMusicPath', 'GetSharedMusicPath',
    'GetMoviesPath', 'GetSharedMoviesPath', 'GetDownloadsPath', 'GetSharedDownloadsPath', 'GetAlarmsPath',
    'GetSharedAlarmsPath', 'GetRingtonesPath', 'GetSharedRingtonesPath');
  // System.IOUtils.TDirectory
  cDirectoryDirectories: array[0..1] of string = ('GetCurrentDirectory', 'GetParent');
  // Letzter Ordner unter Windows, für die Meldung (Paare Funktion, Ordner).
  cTypicalFolders: array[0..17] of string = ('GetDocumentsPath', 'Documents', 'GetSharedDocumentsPath', 'Documents',
    'GetPicturesPath', 'Pictures', 'GetMusicPath', 'Music', 'GetMoviesPath', 'Videos', 'GetDownloadsPath',
    'Downloads', 'GetHomePath', 'Roaming', 'GetCachePath', 'Local', 'GetPublicPath', 'ProgramData');
  // Rechte Seiten, die kein Datei- oder Ordnername sind.
  cNotNames: array[0..9] of string = ('PathDelim', 'DirectorySeparatorChar', 'AltDirectorySeparatorChar',
    'PathSeparator', 'DriveDelim', 'sLineBreak', 'ExtractFileExt', 'GetExtension', 'IncludeTrailingPathDelimiter',
    'IncludeTrailingBackslash');
  cNotNameParts: array[0..3] of string = ('Delim', 'Separator', 'Extension', 'LineBreak');
  // Prozeduren, die einen Pfad nur lesen; jede andere Prozedur könnte ihn als var-Parameter ändern.
  cReadingCalls: array[0..13] of string = ('ForceDirectories', 'CreateDir', 'RemoveDir', 'SetCurrentDir',
    'DirectoryExists', 'FileExists', 'CreateDirectory', 'Delete', 'ShowMessage', 'Writeln', 'Assert', 'Log',
    'SaveToFile', 'LoadFromFile');

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

// Iterativ (Bericht M1): erst die Punktkette hinab, dann die Namen von innen nach außen anhängen.
function DottedText(ANode: TSyntaxNode): string;
var
  mChain: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mChain := TStack<TSyntaxNode>.Create;
  try
    mNode := ANode;
    while (mNode.Kind = TSyntaxKind.MemberAccess) and (mNode.ChildCount = 1) do
    begin
      mChain.Push(mNode);
      mNode := mNode[0];
    end;
    Result := '';
    if mNode.Kind = TSyntaxKind.Identifier then
    begin
      Result := mNode.Name;
    end;
    while (mChain.Count > 0) and (Result <> '') do
    begin
      Result := Result + '.' + mChain.Pop.Name;
    end;
  finally
    mChain.Free;
  end;
end;

function CalleeName(ANode: TSyntaxNode; out AName, AQualifier: string): Boolean;
var
  mCallee: TSyntaxNode;
begin
  AName := '';
  AQualifier := '';
  mCallee := ANode;
  while (mCallee <> nil) and (mCallee.Kind = TSyntaxKind.ParenExpr) and (mCallee.ChildCount = 1) do
  begin
    mCallee := mCallee[0];
  end;
  if (mCallee <> nil) and (mCallee.Kind = TSyntaxKind.Call) and (mCallee.ChildCount > 0) then
  begin
    mCallee := mCallee[0];
  end;
  if mCallee = nil then
  begin
    Exit(False);
  end;
  if mCallee.Kind = TSyntaxKind.Identifier then
  begin
    AName := mCallee.Name;
  end
  else if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) then
  begin
    AQualifier := DottedText(mCallee[0]);
    if AQualifier = '' then
    begin
      Exit(False);
    end;
    AName := mCallee.Name;
  end;
  Result := AName <> '';
end;

function QualifierIs(const AQualifier, AType: string): Boolean;
begin
  Result := SameText(AQualifier, AType) or EndsText('.' + AType, AQualifier);
end;

class function TPathConcatWithoutDelimiterRule.DirectorySource(ANode: TSyntaxNode): string;
var
  mName, mQualifier: string;
begin
  Result := '';
  if not CalleeName(ANode, mName, mQualifier) then
  begin
    Exit;
  end;
  if ((mQualifier = '') or QualifierIs(mQualifier, 'SysUtils')) and MatchText(mName, cSysUtilsDirectories) then
  begin
    Result := mName;
  end
  else if QualifierIs(mQualifier, 'TPath') and MatchText(mName, cPathDirectories) then
  begin
    Result := mName;
  end
  else if QualifierIs(mQualifier, 'TDirectory') and MatchText(mName, cDirectoryDirectories) then
  begin
    Result := mName;
  end;
end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

function IsPlus(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '+') and (ANode.ChildCount = 2);
end;

/// <summary>Letzter Summand von ANode (bei A + B + C der Teil C).</summary>
function LastTerm(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := Unwrapped(ANode);
  while IsPlus(Result) do
  begin
    Result := Unwrapped(Result[1]);
  end;
end;

/// <summary>Erster Summand von ANode (bei A + B + C der Teil A).</summary>
function FirstTerm(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := Unwrapped(ANode);
  while IsPlus(Result) do
  begin
    Result := Unwrapped(Result[0]);
  end;
end;

function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Ist AName eine lokale Variable von ARoutine (var-Abschnitt oder Inline-Variable)?</summary>
function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mFound: Boolean;
begin
  mFound := False;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ((ANode.Kind = TSyntaxKind.VarDecl) and MatchText(AName, SplitString(StringReplace(ANode.Name, ' ', '',
        [rfReplaceAll]), ','))) or ((ANode.Kind = TSyntaxKind.InlineVar) and SameText(ANode.Name, AName)) then
      begin
        mFound := True;
      end;
      // Verschachtelte Routinen haben eigene Variablen.
      Result := not mFound and ((ANode = ARoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
    end);
  Result := mFound;
end;

/// <summary>Wert, den ANode der Variablen AName gibt (Zuweisung oder Inline-Variable mit Wert); nil ohne.
/// </summary>
function AssignedValue(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
begin
  Result := nil;
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName) then
  begin
    Result := ANode[1];
  end
  else if (ANode.Kind = TSyntaxKind.InlineVar) and SameText(ANode.Name, AName) and (ANode.ChildCount > 0) and
    (ANode[ANode.ChildCount - 1].Kind <> TSyntaxKind.TypeReference) then
  begin
    Result := ANode[ANode.ChildCount - 1];
  end;
end;

/// <summary>Ist ANode der Aufruf einer Prozedur außerhalb von ReadingCalls (als Anweisung)?</summary>
function IsWritingCall(ANode: TSyntaxNode): Boolean;
var
  mCallee, mQualifier: string;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind = TSyntaxKind.CallStatement) and CalleeName(ANode, mCallee, mQualifier) and
    not MatchText(mCallee, cReadingCalls);
end;

/// <summary>Geht die Variable AName an den Aufruf ANode einer Prozedur außerhalb von ReadingCalls (vielleicht
/// ein var-Parameter)?</summary>
function PassedToProcedure(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  if not IsWritingCall(ANode) then
  begin
    Exit(False);
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].Kind = TSyntaxKind.Identifier) and SameText(ANode[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Quelle aller Werte der lokalen Variablen AName in ARoutine; '' wenn eine Zuweisung keinen Ordner
/// ohne Trennzeichen liefert oder die Variable an eine Prozedur außerhalb von ReadingCalls geht (vielleicht
/// ein var-Parameter).</summary>
function VariableSource(ARoutine: TSyntaxNode; const AName: string): string;
var
  mSource: string;
  mMixed: Boolean;
begin
  mSource := '';
  mMixed := False;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mValue: TSyntaxNode;
      mFound: string;
    begin
      Result := not mMixed;
      if mMixed then
      begin
        Exit;
      end;
      mValue := AssignedValue(ANode, AName);
      if mValue <> nil then
      begin
        mFound := TPathConcatWithoutDelimiterRule.DirectorySource(mValue);
        mMixed := (mFound = '') or ((mSource <> '') and not SameText(mFound, mSource));
        mSource := mFound;
      end
      else
      begin
        mMixed := PassedToProcedure(ANode, AName);
      end;
    end);
  if mMixed then
  begin
    Result := '';
  end
  else
  begin
    Result := mSource;
  end;
end;

/// <summary>Ist ANode ein Datei- oder Ordnername (Literal, das mit einem Buchstaben, einer Ziffer oder _ beginnt,
/// oder ein Bezeichner, der kein Trennzeichen und keine Endung ist)? AText: Klartext des Literals.</summary>
function IsNamePart(ANode: TSyntaxNode; out AIsLiteral: Boolean; out AText: string): Boolean;
var
  mName, mQualifier, mPart: string;
begin
  Result := False;
  AIsLiteral := False;
  AText := '';
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    if not StartsStr('''', ANode.Name) or not TStringLiterals.PlainText(ANode.Name, AText) or (AText = '') then
    begin
      Exit;
    end;
    AIsLiteral := True;
    Result := TTextChars.IsIdentChar(AText[1]);
    Exit;
  end;
  if not CalleeName(ANode, mName, mQualifier) or MatchText(mName, cNotNames) then
  begin
    Exit;
  end;
  for mPart in cNotNameParts do
  begin
    if ContainsText(mName, mPart) then
    begin
      Exit;
    end;
  end;
  Result := not EndsText('Ext', mName);
end;

function TypicalFolder(const ASource: string): string;
var
  mIndex: Integer;
begin
  mIndex := 0;
  while mIndex < High(cTypicalFolders) do
  begin
    if SameText(cTypicalFolders[mIndex], ASource) then
    begin
      Exit(cTypicalFolders[mIndex + 1]);
    end;
    Inc(mIndex, 2);
  end;
  Result := cTexts[TFilesText.Folder].Text;
end;

{ TPathConcatWithoutDelimiterRule }

function TPathConcatWithoutDelimiterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPathConcatWithoutDelimiterRuleId, TRuleSeverity.Warning,
    cTexts[TFilesText.ConcatTitle].Text);
end;

procedure TPathConcatWithoutDelimiterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mText, mLineBreak: string;
  mUsed: TArray<string>;
  mPluses: TArray<TSyntaxNode>;
  mPlus: TSyntaxNode;

  function Fixes(APlus, ALeft, ARight: TSyntaxNode): TArray<TRuleFix>;
  var
    mEdits: TArray<TRuleEdit>;
    mUsesEdit: TRuleEdit;
  begin
    Result := nil;
    // Nur wenn der Ausdruck genau Ordner + Name ist; bei Präfix + Ordner + Name wäre umzustellen.
    if (Unwrapped(APlus[0]) <> ALeft) or (Unwrapped(APlus[1]) <> ARight) then
    begin
      Exit;
    end;
    mEdits := [TRuleEdit.Create(TTextRange.Create(APlus.StartPos, APlus.EndPos),
      Format('TPath.Combine(%s, %s)', [SourceText(mText, APlus[0]), SourceText(mText, APlus[1])]))];
    if not TUsesClauses.IsUsed(mUsed, 'System.IOUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, APlus.StartOffset, 'System.IOUtils', mLineBreak, mUsesEdit) then
    begin
      mEdits := mEdits + [mUsesEdit];
    end;
    Result := [TRuleFix.Create(cTexts[TFilesText.UseCombine].Text, mEdits)];
  end;

  procedure CheckPlus(APlus: TSyntaxNode);
  var
    mLeft, mRight, mRoutine: TSyntaxNode;
    mSource, mSubject, mPlain, mMessage: string;
    mIsLiteral: Boolean;
    mConfidence: TRuleConfidence;
  begin
    mLeft := LastTerm(APlus[0]);
    mRight := FirstTerm(APlus[1]);
    if not IsNamePart(mRight, mIsLiteral, mPlain) then
    begin
      Exit;
    end;
    mSource := DirectorySource(mLeft);
    if mSource <> '' then
    begin
      mSubject := cTexts[TFilesText.Returns].Fmt([mSource]);
    end
    else
    begin
      if mLeft.Kind <> TSyntaxKind.Identifier then
      begin
        Exit;
      end;
      mRoutine := EnclosingRoutine(mLeft);
      if (mRoutine = nil) or not IsLocal(mRoutine, mLeft.Name) then
      begin
        Exit;
      end;
      mSource := VariableSource(mRoutine, mLeft.Name);
      if mSource = '' then
      begin
        Exit;
      end;
      mSubject := cTexts[TFilesText.ComesFrom].Fmt([mLeft.Name, mSource]);
    end;
    if mIsLiteral then
    begin
      mMessage := cTexts[TFilesText.NoBackslashLiteral].Fmt([mSubject, TypicalFolder(mSource), mPlain]);
      mConfidence := TRuleConfidence.High;
    end
    else
    begin
      mMessage := cTexts[TFilesText.NoBackslash].Fmt([mSubject, SourceText(mText, mRight)]);
      mConfidence := TRuleConfidence.Medium;
    end;
    AReport.Add(TTextRange.Create(mLeft.StartPos, mRight.EndPos), mMessage, mConfidence, Fixes(APlus, mLeft, mRight));
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mText := AContext.Text;
  mLineBreak := TTextLines.LineBreakOf(mText);
  mUsed := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  mPluses := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if IsPlus(ANode) then
      begin
        mPluses := mPluses + [ANode];
      end;
      Result := True;
    end);
  for mPlus in mPluses do
  begin
    CheckPlus(mPlus);
  end;
end;

{ THardcodedPathRule }

const
  cUserFolders: array[0..1] of string = ('Users', 'Documents and Settings');

function THardcodedPathRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cHardcodedPathRuleId, TRuleSeverity.Hint, cTexts[TFilesText.PathTitle].Text);
end;

function IsSlash(AC: Char): Boolean;
begin
  Result := (AC = '\') or (AC = '/');
end;

/// <summary>C:\Ordner…: erster Ordner entscheidet über Benutzerpfade.</summary>
function DriveKind(const APath: string): THardcodedPathKind;
var
  mIndex: Integer;
  mFolder: string;
begin
  mIndex := 4;
  while (mIndex <= Length(APath)) and not IsSlash(APath[mIndex]) do
  begin
    Inc(mIndex);
  end;
  mFolder := Copy(APath, 4, mIndex - 4);
  if MatchText(mFolder, cUserFolders) and (mIndex < Length(APath)) then
  begin
    Result := THardcodedPathKind.UserFolder;
  end
  else
  begin
    Result := THardcodedPathKind.Drive;
  end;
end;

/// <summary>\\server\freigabe; \\?\ und \\.\ sind Präfixe bzw. Geräte.</summary>
function NetworkKind(const APath: string): THardcodedPathKind;
var
  mIndex: Integer;
begin
  Result := THardcodedPathKind.None;
  mIndex := 3;
  while (mIndex <= Length(APath)) and not IsSlash(APath[mIndex]) and (APath[mIndex] > ' ') do
  begin
    Inc(mIndex);
  end;
  if (mIndex < Length(APath)) and IsSlash(APath[mIndex]) then
  begin
    Result := THardcodedPathKind.Network;
  end;
end;

/// <summary>Beginnt APath mit Laufwerk und Ordner (C:\x)? Die Laufwerkswurzel 'C:\' allein bleibt still.
/// </summary>
function IsDrivePath(const APath: string): Boolean;
begin
  Result := (Length(APath) > 3) and CharInSet(APath[1], ['A'..'Z', 'a'..'z']) and (APath[2] = ':');
  Result := Result and IsSlash(APath[3]) and not IsSlash(APath[4]);
end;

class function THardcodedPathRule.PathKind(const APath: string): THardcodedPathKind;
begin
  Result := THardcodedPathKind.None;
  if IsDrivePath(APath) then
  begin
    Result := DriveKind(APath);
  end
  else if (Length(APath) > 3) and (APath[1] = '\') and (APath[2] = '\') and TTextChars.IsIdentChar(APath[3]) then
  begin
    Result := NetworkKind(APath);
  end;
end;

class function THardcodedPathRule.UnitAllowed(const AUnitName: string; const AAllowed: TArray<string>): Boolean;
var
  mItem: string;
begin
  for mItem in AAllowed do
  begin
    if SameText(mItem, AUnitName) or (EndsStr('*', mItem) and StartsText(Copy(mItem, 1, Length(mItem) - 1),
      AUnitName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure THardcodedPathRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mToken: TPascalToken;
  mUnitName, mPlain, mMessage: string;
begin
  mTokens := TRuleDerived.CodeTokens(TRuleDerived.Open(AContext), AContext);
  if TRuleProfiles.IsTestUnit(mTokens) then
  begin
    Exit;
  end;
  mUnitName := TUsesClauses.OwnName(mTokens);
  if mUnitName = '' then
  begin
    mUnitName := AContext.UnitName;
  end;
  if THardcodedPathRule.UnitAllowed(mUnitName, TRuleOptions.Strings(AContext.Options, 'allowUnits', nil)) then
  begin
    Exit;
  end;
  for mToken in mTokens do
  begin
    if (mToken.Kind <> TPascalTokenKind.StringLiteral) or not TStringLiterals.PlainText(mToken.Text, mPlain) then
    begin
      Continue;
    end;
    case PathKind(mPlain) of
      THardcodedPathKind.Drive:
        mMessage := cTexts[TFilesText.FixedPath].Text;
      THardcodedPathKind.UserFolder:
        mMessage := cTexts[TFilesText.UserPath].Text;
      THardcodedPathKind.Network:
        mMessage := cTexts[TFilesText.NetworkPath].Text;
    else
      Continue;
    end;
    AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), mMessage, TRuleConfidence.High);
  end;
end;

{ TFilenameCompareCaseRule }

const
  // System.SysUtils: liefern Datei- oder Pfadnamen.
  cSysUtilsFileNames: array[0..10] of string = ('ExtractFileName', 'ExtractFilePath', 'ExtractFileDir',
    'ExtractFileExt', 'ExpandFileName', 'ExpandUNCFileName', 'ChangeFileExt', 'ExtractRelativePath',
    'ExcludeTrailingPathDelimiter', 'IncludeTrailingPathDelimiter', 'GetCurrentDir');
  // System.IOUtils.TPath
  cPathFileNames: array[0..7] of string = ('GetFileName', 'GetFileNameWithoutExtension', 'GetExtension',
    'GetDirectoryName', 'GetFullPath', 'Combine', 'ChangeExtension', 'GetTempFileName');

function TFilenameCompareCaseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cFilenameCompareCaseRuleId, TRuleSeverity.Hint, cTexts[TFilesText.CompareTitle].Text);
end;

class function TFilenameCompareCaseRule.IsFileNameExpression(ANode: TSyntaxNode): Boolean;
var
  mName, mQualifier: string;
  mNode: TSyntaxNode;
begin
  mNode := Unwrapped(ANode);
  Result := False;
  if not CalleeName(mNode, mName, mQualifier) then
  begin
    Exit;
  end;
  if ((mQualifier = '') or QualifierIs(mQualifier, 'SysUtils')) and MatchText(mName, cSysUtilsFileNames) then
  begin
    Exit(True);
  end;
  if QualifierIs(mQualifier, 'TPath') and MatchText(mName, cPathFileNames) then
  begin
    Exit(True);
  end;
  // Eigenschaften und Variablen: X.FileName, AFileName, Application.ExeName (kein Aufruf mit Argumenten)
  if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount > 1) then
  begin
    Exit;
  end;
  Result := EndsText('FileName', mName) or SameText(mName, 'ExeName');
end;

/// <summary>Kann ANode als Vergleichspartner eines Dateinamens Groß-/Kleinschreibung haben? Leertext,
/// nil, Zahlen und Literale ohne Buchstaben nicht.</summary>
function HasCase(ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
  mPlain: string;
  C: Char;
begin
  mNode := Unwrapped(ANode);
  if mNode.Kind = TSyntaxKind.Literal then
  begin
    if not StartsStr('''', mNode.Name) or not TStringLiterals.PlainText(mNode.Name, mPlain) then
    begin
      Exit(False);
    end;
    for C in mPlain do
    begin
      if UpperCase(C) <> LowerCase(C) then
      begin
        Exit(True);
      end;
    end;
    Exit(False);
  end;
  Result := not ((mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, 'nil'));
end;

/// <summary>Ist eine Seite aus der anderen abgeleitet (ExtractFileDir(X) = X, die Wurzel ist erreicht)? Dann
/// stammen beide aus demselben Text, die Schreibweise ist gleich.</summary>
function DerivedFromOther(const AText: string; ALeft, ARight: TSyntaxNode): Boolean;

  function Derives(ACall, AOther: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
    mOther: string;
  begin
    Result := False;
    if ACall.Kind <> TSyntaxKind.Call then
    begin
      Exit;
    end;
    mOther := SourceText(AText, AOther);
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      if SameText(SourceText(AText, Unwrapped(ACall[mIndex])), mOther) then
      begin
        Exit(True);
      end;
    end;
  end;

begin
  Result := Derives(Unwrapped(ALeft), Unwrapped(ARight)) or Derives(Unwrapped(ARight), Unwrapped(ALeft));
end;

const
  // Vergleiche ohne Groß-/Kleinschreibung aus System.SysUtils.
  cIgnoreCaseCompares: array[0..5] of string = ('SameText', 'AnsiSameText', 'CompareText', 'AnsiCompareText',
    'SameFileName', 'AnsiCompareFileName');

/// <summary>Gehört ANode noch zur selben Anweisung wie sein Kind? Ausdrücke, Zuweisungen, Aufrufe und
/// Verzweigungen ja; der begin-end-Block eines Zweigs auch, Rumpf von Routine oder Schleife nicht.</summary>
function SameStatement(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.IfExpr, TSyntaxKind.Call,
    TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
    TSyntaxKind.CaseItem, TSyntaxKind.CaseElse:
      Result := True;
    TSyntaxKind.Block:
      Result := (ANode.Parent <> nil) and (ANode.Parent.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.CaseItem,
        TSyntaxKind.CaseElse]);
  else
    Result := False;
  end;
end;

/// <summary>Ist ANode ein Vergleich ohne Groß-/Kleinschreibung mit zwei Argumenten (SameText, CompareText …
/// ohne oder mit SysUtils davor)?</summary>
function IsIgnoreCaseCompare(ANode: TSyntaxNode): Boolean;
var
  mName, mQualifier: string;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 3) and CalleeName(ANode, mName, mQualifier);
  Result := Result and ((mQualifier = '') or QualifierIs(mQualifier, 'SysUtils')) and
    MatchText(mName, cIgnoreCaseCompares);
end;

class function TFilenameCompareCaseRule.ComparedIgnoringCase(const AText: string; ACompare: TSyntaxNode): Boolean;
var
  mScope: TSyntaxNode;
  mLeft, mRight: string;
  mFound: Boolean;
begin
  mScope := ACompare;
  while (mScope.Parent <> nil) and SameStatement(mScope.Parent) do
  begin
    mScope := mScope.Parent;
  end;
  mLeft := SourceText(AText, Unwrapped(ACompare[0]));
  mRight := SourceText(AText, Unwrapped(ACompare[1]));
  mFound := False;
  mScope.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      First, Second: string;
    begin
      if not mFound and IsIgnoreCaseCompare(ANode) then
      begin
        First := SourceText(AText, Unwrapped(ANode[1]));
        Second := SourceText(AText, Unwrapped(ANode[2]));
        mFound := (SameText(First, mLeft) and SameText(Second, mRight)) or
          (SameText(First, mRight) and SameText(Second, mLeft));
      end;
      Result := not mFound;
    end);
  Result := mFound;
end;

/// <summary>Vergleicht ANode (= oder &lt;&gt;) einen Dateinamen genau nach Groß-/Kleinschreibung, obwohl beide
/// Seiten sie haben können und die Anweisung nicht auch ohne vergleicht?</summary>
function IsCaseSensitiveCompare(const AText: string; ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and MatchStr(ANode.Name, ['=', '<>']) and (ANode.ChildCount = 2);
  Result := Result and (TFilenameCompareCaseRule.IsFileNameExpression(ANode[0]) or
    TFilenameCompareCaseRule.IsFileNameExpression(ANode[1])) and HasCase(ANode[0]) and HasCase(ANode[1]);
  Result := Result and not DerivedFromOther(AText, ANode[0], ANode[1]) and
    not TFilenameCompareCaseRule.ComparedIgnoringCase(AText, ANode);
end;

/// <summary>Korrektur: SameFileName statt des Vergleichs ACompare, System.SysUtils bei Bedarf in uses.</summary>
function SameFileNameEdits(const AContext: TRuleContext; ACompare: TSyntaxNode;
  const AUsed: TArray<string>): TArray<TRuleEdit>;
var
  mUsesEdit: TRuleEdit;
  mNewText: string;
begin
  mNewText := Format('SameFileName(%s, %s)', [SourceText(AContext.Text, ACompare[0]),
    SourceText(AContext.Text, ACompare[1])]);
  if ACompare.Name = '<>' then
  begin
    mNewText := 'not ' + mNewText;
  end;
  Result := [TRuleEdit.Create(TTextRange.Create(ACompare.StartPos, ACompare.EndPos), mNewText)];
  if not TUsesClauses.IsUsed(AUsed, 'System.SysUtils', AContext.Namespaces) and
    TUsesClauses.AddUnit(AContext.Tree.Tokens, ACompare.StartOffset, 'System.SysUtils',
    TTextLines.LineBreakOf(AContext.Text), mUsesEdit) then
  begin
    Result := Result + [mUsesEdit];
  end;
end;

procedure TFilenameCompareCaseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCompares: TArray<TSyntaxNode>;
  mCompare: TSyntaxNode;
  mUsed: TArray<string>;
  mText: string;
begin
  // Testdoubles vergleichen mit Namen, die der Test selbst vergibt; dort ist der genaue Vergleich gewollt.
  if (AContext.Tree = nil) or TRuleProfiles.IsTestUnit(AContext.Tree.Tokens) then
  begin
    Exit;
  end;
  mCompares := nil;
  mText := AContext.Text;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if IsCaseSensitiveCompare(mText, ANode) then
      begin
        mCompares := mCompares + [ANode];
      end;
      Result := True;
    end);
  if mCompares = nil then
  begin
    Exit;
  end;
  mUsed := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  for mCompare in mCompares do
  begin
    AReport.Add(TTextRange.Create(mCompare.StartPos, mCompare.EndPos),
      cTexts[TFilesText.CaseInsensitive].Text,
      TRuleConfidence.Medium, [TRuleFix.Create(cTexts[TFilesText.UseSameFileName].Text, SameFileNameEdits(AContext,
        mCompare,
      mUsed))]);
  end;
end;

procedure RegisterFileRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPathConcatWithoutDelimiterRule.Create);
  ARegistry.Register(THardcodedPathRule.Create);
  ARegistry.Register(TFilenameCompareCaseRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Files', cTexts);

end.
