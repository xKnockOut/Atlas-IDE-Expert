unit Atlas.Common.Lsp.MoveClass;

// „Klasse in eigene Unit verschieben“ über das Protokoll (#103 Teil B):
//   - Code-Aktion „Klasse TFoo in eigene Unit verschieben …“ auf der ersten
//     Zeile einer Klassendeklaration, nur wenn refactoring.moveClass an ist
//     und sich die Klasse verschieben lässt. Sie trägt den Client-Befehl
//     atlas.moveClass mit [uri, position, vorgeschlagener Name]; das Plugin
//     fragt den Namen ab (Klassenname ohne T, abweichend wählbar).
//   - Befehl atlas.server.moveClass [uri, position, name]: WorkspaceEdit mit
//     documentChanges: neue Datei neben der Ursprungs-Unit anlegen und füllen,
//     Ursprungs-Unit ändern, die neue Unit in uses bzw. contains der .dpr/.dpk
//     und als DCCReference in die .dproj eintragen, und alle Units, die die
//     Klasse verwenden (Referenzsuche, #29), erhalten die neue Unit im uses.
// Die Namensauflösung bestimmt, aus welcher Unit jeder benötigte Name stammt;
// die Logik liegt in Atlas.Common.Editing.MoveClass.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.References;

type
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TMoveClassExists = reference to function(const AFileName: string): Boolean;

  TMoveClassContext = record
    Index: ISymbolIndex;
    /// <summary>Projekt der Datei; ohne Projekt wird nur die Unit angelegt.</summary>
    HasProject: Boolean;
    Project: TProjectInfo;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    Exists: TMoveClassExists;
    /// <summary>Name der neuen Unit.</summary>
    UnitName: string;
    /// <summary>Typkommentar { TKunde } mitnehmen (#1838); aus mit classCompletion.typeComment = off.</summary>
    TypeComments: Boolean;
  end;

  TLspMoveClass = class
  public const
    cClientCommand = 'atlas.moveClass';
    cApplyCommand = 'atlas.server.moveClass';
  public
    /// <summary>Namensauflösung für den Kern über AResolver.</summary>
    class function Lookup(AResolver: TNameResolver): TMoveClassLookup; static;
    /// <summary>Die Code-Aktion an APosition, wenn die Klasse dort verschiebbar ist; sonst nil. Ob die Funktion
    /// eingeschaltet ist, prüft der Aufrufer. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>{"edit": WorkspaceEdit, "file": URI der neuen Unit, "warnings": [...]}; EJsonRpcError, wenn die
    /// Klasse nicht verschiebbar ist oder die Datei schon existiert. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TMoveClassContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.WorkspaceChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspMoveClassText = (ThereIsNoClassAt, UnknownOriginOfTheNew, MoveClass, MoveClassIntoItsOwn, AlreadyExists,
    IsAlreadyInTheProject);

const
  cTexts: array[TLspMoveClassText] of TAtlasText = (
    (De: 'an dieser Stelle steht keine Klasse'; En: 'there is no class at this position'),
    (De: 'Unbekannte Herkunft von %s: Die neue Unit übernimmt dafür die uses der Ursprungs-Unit.';
     En: 'Unknown origin of %s: the new unit takes over the uses of the original unit for it.'),
    (De: 'Klasse verschieben: '; En: 'Move class: '),
    (De: 'Klasse %s in eigene Unit verschieben …'; En: 'Move class %s into its own unit …'),
    (De: '%s gibt es schon'; En: '%s already exists'),
    (De: '%s steht schon im Projekt'; En: '%s is already in the project'));

{$SCOPEDENUMS OFF}

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.cRequestFailed, cTexts[TLspMoveClassText.MoveClass].Text + AMessage);
end;

function IsSource(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']);
end;

class function TLspMoveClass.Lookup(AResolver: TNameResolver): TMoveClassLookup;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TMoveClassMeaning
    var
      Resolved: TResolvedSymbol;
    begin
      Result := Default(TMoveClassMeaning);
      Resolved := AResolver.ResolveChain(ATree, AFileName, ANames, AOffset);
      case Resolved.Kind of
        TResolvedKind.Local:
          begin
            Result.Found := True;
            Result.IsLocal := True;
          end;
        TResolvedKind.UnitName, TResolvedKind.Symbol:
          begin
            Result.Found := True;
            Result.UnitName := Resolved.UnitName;
            Result.FileName := Resolved.FileName;
            Result.Position := Resolved.Range.StartPos;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
end;

class function TLspMoveClass.Actions(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
var
  mDecl: TSyntaxNode;
  mPlan: TMoveClassPlan;
  mReason, mTitle, mName: string;
  mArguments: TJSONArray;
  mCommand, mAction: TJSONObject;
begin
  Result := nil;
  mDecl := TMoveClass.ClassAt(ATree, APosition);
  if mDecl = nil then
  begin
    Exit;
  end;
  mName := TMoveClass.DefaultUnitName(mDecl.Name);
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(TMoveClassSource.Create(AFileName, AText, ATree), APosition, mName, Lookup(AResolver), mPlan,
      mReason) then
    begin
      Exit;
    end;
  finally
    AResolver.UnpinTree;
  end;
  mTitle := cTexts[TLspMoveClassText.MoveClassIntoItsOwn].Fmt([mPlan.ClassName]);
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(mName);
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', mTitle);
  mCommand.AddPair('command', cClientCommand);
  mCommand.AddPair('arguments', mArguments);
  mAction := TJSONObject.Create;
  mAction.AddPair('title', mTitle);
  mAction.AddPair('kind', TMoveClass.cKind);
  mAction.AddPair('command', mCommand);
  Result := [mAction];
end;

/// <summary>EJsonRpcError, wenn es die Datei ANewFile oder die Unit im Projekt schon gibt.</summary>
procedure CheckNewUnit(const AContext: TMoveClassContext; const APlan: TMoveClassPlan; const ANewFile: string);
var
  mItem: TProjectUnit;
begin
  if Assigned(AContext.Exists) and AContext.Exists(ANewFile) then
  begin
    raise Failed(cTexts[TLspMoveClassText.AlreadyExists].Fmt([ExtractFileName(ANewFile)]));
  end;
  if not AContext.HasProject then
  begin
    Exit;
  end;
  for mItem in AContext.Project.Units do
  begin
    if SameText(mItem.Name, APlan.NewUnit) then
    begin
      raise Failed(cTexts[TLspMoveClassText.IsAlreadyInTheProject].Fmt([APlan.NewUnit]));
    end;
  end;
end;

/// <summary>Quelldateien mit Verweisen außer AFileName, jede einmal.</summary>
function UserFiles(const AReferences: TArray<TReferenceLocation>; const AFileName: string): TArray<string>;
var
  mLocation: TReferenceLocation;
begin
  Result := nil;
  for mLocation in AReferences do
  begin
    if not SameText(mLocation.FileName, AFileName) and IsSource(mLocation.FileName) and
      (IndexText(mLocation.FileName, Result) < 0) then
    begin
      Result := Result + [mLocation.FileName];
    end;
  end;
end;

/// <summary>Verweise in der Datei AUser.</summary>
function RangesOf(const AReferences: TArray<TReferenceLocation>; const AUser: string): TArray<TTextRange>;
var
  mLocation: TReferenceLocation;
begin
  Result := nil;
  for mLocation in AReferences do
  begin
    if SameText(mLocation.FileName, AUser) then
    begin
      Result := Result + [mLocation.Range];
    end;
  end;
end;

/// <summary>uses der verwendenden Units; die Hauptdatei des Projekts erhält die Unit unten mit Pfad.</summary>
procedure AddUserEdits(AChanges: TWorkspaceChanges; const AContext: TMoveClassContext; const APlan: TMoveClassPlan;
  const AReferences: TArray<TReferenceLocation>; const AFileName: string);
var
  mMainSource, mUser, mText: string;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mMainSource := '';
  if AContext.HasProject then
  begin
    mMainSource := AContext.Project.MainSource;
  end;
  for mUser in UserFiles(AReferences, AFileName) do
  begin
    if not (Assigned(AContext.ReadText) and AContext.ReadText(mUser, mText)) then
    begin
      Continue;
    end;
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      if TMoveClass.UpdateUser(mText, mTree, APlan.Names, RangesOf(AReferences, mUser),
        not SameText(mUser, mMainSource), mEdits) then
      begin
        AChanges.Add(mUser, mEdits);
      end;
    finally
      mTree.Free;
    end;
  end;
end;

class function TLspMoveClass.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TMoveClassContext): TJSONObject;
var
  mPlan: TMoveClassPlan;
  mSource: TMoveClassSource;
  mReason, mNewFile: string;
  mDecl: TSyntaxNode;
  mChanges: TWorkspaceChanges;
  mReferences: TArray<TReferenceLocation>;
begin
  mDecl := TMoveClass.ClassAt(ATree, APosition);
  if mDecl = nil then
  begin
    raise Failed(cTexts[TLspMoveClassText.ThereIsNoClassAt].Text);
  end;
  mSource := TMoveClassSource.Create(AFileName, AText, ATree);
  mSource.TypeComments := AContext.TypeComments;
  AResolver.PinTree(ATree, AFileName);
  try
    if not TMoveClass.Plan(mSource, APosition, AContext.UnitName, Lookup(AResolver), mPlan, mReason) then
    begin
      raise Failed(mReason);
    end;
    mNewFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFileName), mPlan.NewUnit + '.pas');
    CheckNewUnit(AContext, mPlan, mNewFile);
    // Verwendende Units über die Referenzsuche (#29).
    mReferences := TLspReferences.Find(AResolver, AContext.Index, ATree, TReferenceSearch.Create(AFileName,
      mDecl.StartPos, False, AContext.Files, AContext.ReadText));
  finally
    AResolver.UnpinTree;
  end;
  mChanges := TWorkspaceChanges.Create;
  try
    // documentChanges: erst die neue Datei, dann die Änderungen je Datei.
    mChanges.CreateFile(mNewFile, mPlan.Text);
    mChanges.Add(AFileName, mPlan.OriginEdits);
    AddUserEdits(mChanges, AContext, mPlan, mReferences, AFileName);
    // Projekt: uses bzw. contains der .dpr/.dpk und DCCReference der .dproj, jeweils mit relativem Pfad.
    mChanges.RegisterUnit(AContext.HasProject, AContext.Project, AContext.ReadText, mNewFile, mPlan.NewUnit);
    if mPlan.Unresolved <> nil then
    begin
      mChanges.Warn(cTexts[TLspMoveClassText.UnknownOriginOfTheNew].Fmt([string.Join(', ', mPlan.Unresolved)]));
    end;
    Result := TJSONObject.Create;
    Result.AddPair('edit', mChanges.ToJson);
    Result.AddPair('file', TDocumentUris.FromPath(mNewFile));
    Result.AddPair('warnings', mChanges.WarningsJson);
  finally
    mChanges.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MoveClass', cTexts);

end.
