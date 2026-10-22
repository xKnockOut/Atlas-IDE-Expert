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

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  PathConcatWithoutDelimiterRuleId = 'path-concat-without-delimiter';

type
  TPathConcatWithoutDelimiterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Name der Funktion, wenn ANode einen Ordner ohne abschließendes Trennzeichen liefert
    /// (ExtractFileDir, TPath.GetDocumentsPath …); sonst ''.</summary>
    class function DirectorySource(ANode: TSyntaxNode): string; static;
  end;

/// <summary>Name und Qualifizierer eines Aufrufs oder Bezeichners: TPath.GetDocumentsPath ergibt
/// GetDocumentsPath und TPath; ohne Aufruf, Bezeichner oder Punktkette False.</summary>
function CalleeName(ANode: TSyntaxNode; out AName, AQualifier: string): Boolean;

procedure RegisterFileRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Chars,
  Atlas.Text.Lines;

const
  // System.SysUtils: Ordner ohne abschließendes Trennzeichen.
  SysUtilsDirectories: array[0..4] of string = ('ExtractFileDir', 'ExcludeTrailingPathDelimiter',
    'ExcludeTrailingBackslash', 'GetCurrentDir', 'GetHomePath');
  // System.IOUtils.TPath: Ordner ohne abschließendes Trennzeichen (GetTempPath hat eins).
  PathDirectories: array[0..20] of string = ('GetDocumentsPath', 'GetSharedDocumentsPath', 'GetHomePath',
    'GetDirectoryName', 'GetLibraryPath', 'GetCachePath', 'GetPublicPath', 'GetPicturesPath',
    'GetSharedPicturesPath', 'GetCameraPath', 'GetSharedCameraPath', 'GetMusicPath', 'GetSharedMusicPath',
    'GetMoviesPath', 'GetSharedMoviesPath', 'GetDownloadsPath', 'GetSharedDownloadsPath', 'GetAlarmsPath',
    'GetSharedAlarmsPath', 'GetRingtonesPath', 'GetSharedRingtonesPath');
  // System.IOUtils.TDirectory
  DirectoryDirectories: array[0..1] of string = ('GetCurrentDirectory', 'GetParent');
  // Letzter Ordner unter Windows, für die Meldung (Paare Funktion, Ordner).
  TypicalFolders: array[0..17] of string = ('GetDocumentsPath', 'Documents', 'GetSharedDocumentsPath', 'Documents',
    'GetPicturesPath', 'Pictures', 'GetMusicPath', 'Music', 'GetMoviesPath', 'Videos', 'GetDownloadsPath',
    'Downloads', 'GetHomePath', 'Roaming', 'GetCachePath', 'Local', 'GetPublicPath', 'ProgramData');
  // Rechte Seiten, die kein Datei- oder Ordnername sind.
  NotNames: array[0..9] of string = ('PathDelim', 'DirectorySeparatorChar', 'AltDirectorySeparatorChar',
    'PathSeparator', 'DriveDelim', 'sLineBreak', 'ExtractFileExt', 'GetExtension', 'IncludeTrailingPathDelimiter',
    'IncludeTrailingBackslash');
  NotNameParts: array[0..3] of string = ('Delim', 'Separator', 'Extension', 'LineBreak');
  // Prozeduren, die einen Pfad nur lesen; jede andere Prozedur könnte ihn als var-Parameter ändern.
  ReadingCalls: array[0..13] of string = ('ForceDirectories', 'CreateDir', 'RemoveDir', 'SetCurrentDir',
    'DirectoryExists', 'FileExists', 'CreateDirectory', 'Delete', 'ShowMessage', 'Writeln', 'Assert', 'Log',
    'SaveToFile', 'LoadFromFile');

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function DottedText(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) then
  begin
    Result := DottedText(ANode[0]);
    if Result <> '' then
      Result := Result + '.' + ANode.Name;
  end;
end;

function CalleeName(ANode: TSyntaxNode; out AName, AQualifier: string): Boolean;
var
  Callee: TSyntaxNode;
begin
  AName := '';
  AQualifier := '';
  Callee := ANode;
  while (Callee <> nil) and (Callee.Kind = TSyntaxKind.ParenExpr) and (Callee.ChildCount = 1) do
    Callee := Callee[0];
  if (Callee <> nil) and (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
    Callee := Callee[0];
  if Callee = nil then
    Exit(False);
  if Callee.Kind = TSyntaxKind.Identifier then
    AName := Callee.Name
  else if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) then
  begin
    AQualifier := DottedText(Callee[0]);
    if AQualifier = '' then
      Exit(False);
    AName := Callee.Name;
  end;
  Result := AName <> '';
end;

function QualifierIs(const AQualifier, AType: string): Boolean;
begin
  Result := SameText(AQualifier, AType) or EndsText('.' + AType, AQualifier);
end;

class function TPathConcatWithoutDelimiterRule.DirectorySource(ANode: TSyntaxNode): string;
var
  Name, Qualifier: string;
begin
  Result := '';
  if not CalleeName(ANode, Name, Qualifier) then
    Exit;
  if ((Qualifier = '') or QualifierIs(Qualifier, 'SysUtils')) and MatchText(Name, SysUtilsDirectories) then
    Result := Name
  else if QualifierIs(Qualifier, 'TPath') and MatchText(Name, PathDirectories) then
    Result := Name
  else if QualifierIs(Qualifier, 'TDirectory') and MatchText(Name, DirectoryDirectories) then
    Result := Name;
end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
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
    Result := Unwrapped(Result[1]);
end;

/// <summary>Erster Summand von ANode (bei A + B + C der Teil A).</summary>
function FirstTerm(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := Unwrapped(ANode);
  while IsPlus(Result) do
    Result := Unwrapped(Result[0]);
end;

function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
    Result := Result.Parent;
end;

/// <summary>Ist AName eine lokale Variable von ARoutine (var-Abschnitt oder Inline-Variable)?</summary>
function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Found: Boolean;
begin
  Found := False;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ((ANode.Kind = TSyntaxKind.VarDecl) and MatchText(AName, SplitString(StringReplace(ANode.Name, ' ', '',
        [rfReplaceAll]), ','))) or ((ANode.Kind = TSyntaxKind.InlineVar) and SameText(ANode.Name, AName)) then
        Found := True;
      // Verschachtelte Routinen haben eigene Variablen.
      Result := not Found and ((ANode = ARoutine) or (ANode.Kind <> TSyntaxKind.RoutineDecl));
    end);
  Result := Found;
end;

/// <summary>Quelle aller Werte der lokalen Variablen AName in ARoutine; '' wenn eine Zuweisung keinen Ordner
/// ohne Trennzeichen liefert oder die Variable an eine Prozedur außerhalb von ReadingCalls geht (vielleicht
/// ein var-Parameter).</summary>
function VariableSource(ARoutine: TSyntaxNode; const AName: string): string;
var
  Source: string;
  Mixed: Boolean;
begin
  Source := '';
  Mixed := False;
  ARoutine.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Value: TSyntaxNode;
      Index: Integer;
      Found, Callee, Qualifier: string;
    begin
      Result := not Mixed;
      if Mixed then
        Exit;
      Value := nil;
      if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
        (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName) then
        Value := ANode[1]
      else if (ANode.Kind = TSyntaxKind.InlineVar) and SameText(ANode.Name, AName) and (ANode.ChildCount > 0) and
        (ANode[ANode.ChildCount - 1].Kind <> TSyntaxKind.TypeReference) then
        Value := ANode[ANode.ChildCount - 1]
      else if (ANode.Kind = TSyntaxKind.Call) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.CallStatement) and CalleeName(ANode, Callee, Qualifier) and
        not MatchText(Callee, ReadingCalls) then
      begin
        for Index := 1 to ANode.ChildCount - 1 do
          if (ANode[Index].Kind = TSyntaxKind.Identifier) and SameText(ANode[Index].Name, AName) then
            Mixed := True;
        Exit;
      end
      else
        Exit;
      Found := TPathConcatWithoutDelimiterRule.DirectorySource(Value);
      if (Found = '') or ((Source <> '') and not SameText(Found, Source)) then
        Mixed := True
      else
        Source := Found;
    end);
  if Mixed then
    Result := ''
  else
    Result := Source;
end;

/// <summary>Ist ANode ein Datei- oder Ordnername (Literal, das mit einem Buchstaben, einer Ziffer oder _ beginnt,
/// oder ein Bezeichner, der kein Trennzeichen und keine Endung ist)? AText: Klartext des Literals.</summary>
function IsNamePart(ANode: TSyntaxNode; out AIsLiteral: Boolean; out AText: string): Boolean;
var
  Name, Qualifier, Part: string;
begin
  Result := False;
  AIsLiteral := False;
  AText := '';
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    if not StartsStr('''', ANode.Name) or not TStringLiterals.PlainText(ANode.Name, AText) or (AText = '') then
      Exit;
    AIsLiteral := True;
    Result := TTextChars.IsIdentChar(AText[1]);
    Exit;
  end;
  if not CalleeName(ANode, Name, Qualifier) or MatchText(Name, NotNames) then
    Exit;
  for Part in NotNameParts do
    if ContainsText(Name, Part) then
      Exit;
  Result := not EndsText('Ext', Name);
end;

function TypicalFolder(const ASource: string): string;
var
  Index: Integer;
begin
  Index := 0;
  while Index < High(TypicalFolders) do
  begin
    if SameText(TypicalFolders[Index], ASource) then
      Exit(TypicalFolders[Index + 1]);
    Inc(Index, 2);
  end;
  Result := 'Ordner';
end;

{ TPathConcatWithoutDelimiterRule }

function TPathConcatWithoutDelimiterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PathConcatWithoutDelimiterRuleId, TRuleSeverity.Warning,
    'Pfad ohne Trennzeichen zusammengesetzt');
end;

procedure TPathConcatWithoutDelimiterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Text, LineBreak: string;
  Used: TArray<string>;
  Pluses: TArray<TSyntaxNode>;
  Plus: TSyntaxNode;

  function Fixes(APlus, ALeft, ARight: TSyntaxNode): TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    UsesEdit: TRuleEdit;
  begin
    Result := nil;
    // Nur wenn der Ausdruck genau Ordner + Name ist; bei Präfix + Ordner + Name wäre umzustellen.
    if (Unwrapped(APlus[0]) <> ALeft) or (Unwrapped(APlus[1]) <> ARight) then
      Exit;
    Edits := [TRuleEdit.Create(TTextRange.Create(APlus.StartPos, APlus.EndPos),
      Format('TPath.Combine(%s, %s)', [SourceText(Text, APlus[0]), SourceText(Text, APlus[1])]))];
    if not TUsesClauses.IsUsed(Used, 'System.IOUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, APlus.StartOffset, 'System.IOUtils', LineBreak, UsesEdit) then
      Edits := Edits + [UsesEdit];
    Result := [TRuleFix.Create('TPath.Combine verwenden', Edits)];
  end;

  procedure CheckPlus(APlus: TSyntaxNode);
  var
    Left, Right, Routine: TSyntaxNode;
    Source, Subject, Plain, Message: string;
    IsLiteral: Boolean;
    Confidence: TRuleConfidence;
  begin
    Left := LastTerm(APlus[0]);
    Right := FirstTerm(APlus[1]);
    if not IsNamePart(Right, IsLiteral, Plain) then
      Exit;
    Source := DirectorySource(Left);
    if Source <> '' then
      Subject := Format('%s liefert', [Source])
    else
    begin
      if Left.Kind <> TSyntaxKind.Identifier then
        Exit;
      Routine := EnclosingRoutine(Left);
      if (Routine = nil) or not IsLocal(Routine, Left.Name) then
        Exit;
      Source := VariableSource(Routine, Left.Name);
      if Source = '' then
        Exit;
      Subject := Format('%s kommt aus %s und hat', [Left.Name, Source]);
    end;
    if IsLiteral then
    begin
      Message := Format('%s keinen abschließenden Backslash; das Ergebnis ist …\%s%s.',
        [Subject, TypicalFolder(Source), Plain]);
      Confidence := TRuleConfidence.High;
    end
    else
    begin
      Message := Format('%s keinen abschließenden Backslash; %s wird ohne Trennzeichen angehängt.',
        [Subject, SourceText(Text, Right)]);
      Confidence := TRuleConfidence.Medium;
    end;
    AReport.Add(TTextRange.Create(Left.StartPos, Right.EndPos), Message, Confidence, Fixes(APlus, Left, Right));
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Text := AContext.Text;
  LineBreak := TTextLines.LineBreakOf(Text);
  Used := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  Pluses := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if IsPlus(ANode) then
        Pluses := Pluses + [ANode];
      Result := True;
    end);
  for Plus in Pluses do
    CheckPlus(Plus);
end;

procedure RegisterFileRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPathConcatWithoutDelimiterRule.Create);
end;

end.
