unit Atlas.Common.Lsp.Rename;

// Umbenennen im ganzen Projekt (textDocument/prepareRename und
// textDocument/rename, #30). Grundlage ist die Referenzsuche samt .dfm.
// Umbenannt werden nur Symbole, die im Projekt oder in geöffneten Dokumenten
// deklariert sind; RTL, VCL und andere Bibliotheken bleiben unangetastet.
// Bei Komponenten eines Formulars werden automatisch benannte Ereignis-Handler
// (Button1Click) mit umbenannt (#45).
// Betrifft das Umbenennen ein binär gespeichertes Formular, bricht es ab (#121):
// Die Positionen stammen aus der umgewandelten Textform und passen nicht zur Datei.
// Geändert werden nur sichere Stellen (#1119) und solche in inaktiven Zweigen,
// die eindeutig auf das Symbol auflösen. Die übrigen erschlossenen Stellen
// nennt die Antwort im Feld atlasUnchanged, damit der Editor sie zum Prüfen zeigt.
// Beim Umbenennen eines Typs wandert der Typkommentar über seinen Rümpfen
// ({ TKunde }, // TKunde, {$REGION 'TKunde'}) mit (#1838).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References;

type
  TRenameEdit = record
    FileName: string;
    Range: TTextRange;
    NewText: string;
  end;

  TRenameCheck = record
    /// <summary>'' = umbenennbar; sonst der Grund.</summary>
    Error: string;
    /// <summary>Bereich des Namens unter dem Cursor.</summary>
    Range: TTextRange;
    Name: string;
    /// <summary>Datei mit der Deklaration.</summary>
    DeclarationFile: string;
  end;

  /// <summary>Neuer Name und Art des Umbenennens.</summary>
  TRenameRequest = record
    NewName: string;
    Cancellation: IJsonRpcCancellationToken;
    /// <summary>Handler wie Button1Click beim Umbenennen von Button1 anpassen.</summary>
    RenameHandlers: Boolean;
    /// <summary>Welche erschlossenen Stellen mit geändert werden (#1119).</summary>
    Settings: TReferenceSettings;
    /// <summary>Typkommentare über den Rümpfen mit umbenennen (#1838; aus mit classCompletion.typeComment = off).
    /// </summary>
    TypeComments: Boolean;
    /// <summary>ANewName mit Handlern und Typkommentaren, ohne Abbruch, nur sichere Stellen.</summary>
    class function Create(const ANewName: string): TRenameRequest; overload; static;
    class function Create(const ANewName: string; ARenameHandlers: Boolean; const ASettings: TReferenceSettings;
      const ACancellation: IJsonRpcCancellationToken): TRenameRequest; overload; static;
  end;

  /// <summary>Typkommentare beim Umbenennen anpassen (#1838) je Datei.</summary>
  TRenameTypeCommentsFunc = reference to function(const AUri: string): Boolean;

  TLspRename = class
  public const
    PrepareMethod = 'textDocument/prepareRename';
    RenameMethod = 'textDocument/rename';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FRenameHandlers: Boolean;
    FSettingsFor: TReferenceSettingsProvider;
    FTypeCommentsFor: TRenameTypeCommentsFunc;
    function ProjectFiles: TArray<string>;
    function HandlePrepare(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleRename(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function SettingsOf(const AUri: string): TReferenceSettings;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    class function Capability: TJSONObject; static;
    /// <summary>Prüft, ob das Symbol an APosition umbenannt werden darf; AFiles sind die eigenen Dateien.</summary>
    class function Check(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>): TRenameCheck; static;
    /// <summary>'' oder der Grund, warum ANewName die Bedeutung ändern würde: Eine lokale Variable, ein
    /// Parameter oder ein Feld mit dem neuen Namen verdeckt danach eine umbenannte Stelle, oder das
    /// umbenannte Symbol verdeckt eine vorhandene Verwendung von ANewName. ALocations sind die Stellen aus
    /// TLspReferences.Find samt Deklaration; ASearch nennt Datei, Stelle und das Lesen weiterer Dateien.</summary>
    class function Conflict(AResolver: TNameResolver; ATree: TSyntaxTree; const ASearch: TReferenceSearch;
      const ANewName: string; const ALocations: TArray<TReferenceLocation>): string; static;
    /// <summary>True für einen gültigen Bezeichner, der kein reserviertes Wort ist.</summary>
    class function IsValidName(const AName: string): Boolean; static;
    /// <summary>Alle zu ersetzenden Stellen für das Symbol an ASearch.Position (die Deklaration zählt immer
    /// mit); EJsonRpcError, wenn nicht umbenennbar oder ein betroffenes Formular binär gespeichert ist.
    /// AUnchanged erhält die erschlossenen Stellen nach ARequest.Settings, die nicht geändert werden
    /// (#1119).</summary>
    class function Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch; const ARequest: TRenameRequest;
      out AUnchanged: TArray<TReferenceLocation>): TArray<TRenameEdit>; overload; static;
    /// <summary>Wie oben ohne AUnchanged.</summary>
    class function Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch; const ARequest: TRenameRequest): TArray<TRenameEdit>; overload; static;
    /// <summary>Wie oben mit TRenameRequest.Create(ANewName).</summary>
    class function Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ASearch: TReferenceSearch; const ANewName: string): TArray<TRenameEdit>; overload; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Einstellungen references.* je Datei; nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
    /// <summary>Handler wie Button1Click beim Umbenennen von Button1 anpassen (Standard True).</summary>
    property RenameHandlers: Boolean read FRenameHandlers write FRenameHandlers;
    /// <summary>Typkommentare mit umbenennen (#1838); nicht gesetzt: ja.</summary>
    property TypeCommentsFor: TRenameTypeCommentsFunc read FTypeCommentsFor write FTypeCommentsFor;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Lsp.Internals.Namespaces,
  System.StrUtils,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.ComponentRename,
  Atlas.Common.Editing.TypeComments,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TRenameText = (ThereIsNoIdentifierHere, IsNotKnown, IsDeclaredOutsideTheProject, UnitsAreRenamedViaThe,
    RenamingToWouldChangeThe, IsAFormStoredAs, IsNotAValidIdentifier, FieldsTextDocumentUriAndPosition,
    FieldsTextDocumentUriPositionAnd);

const
  cTexts: array[TRenameText] of TAtlasText = (
    (De: 'Hier steht kein Bezeichner.'; En: 'There is no identifier here.'),
    (De: '"%s" ist nicht bekannt.'; En: '"%s" is not known.'),
    (De: '"%s" ist außerhalb des Projekts deklariert (%s).'; En: '"%s" is declared outside the project (%s).'),
    (De: 'Units werden über den Dateinamen umbenannt.'; En: 'Units are renamed via the file name.'),
    (De: 'Umbenennen in "%s" würde die Bedeutung ändern: In %s, Zeile %d, meinte "%s" danach %s statt %s. Bitte ' +
      'einen anderen Namen wählen oder dort "Self." ergänzen.';
     En: 'Renaming to "%s" would change the meaning: in %s, line %d, "%s" would then mean %s instead of %s. Please ' +
      'choose another name or add "Self." there.'),
    (De: '%s ist ein binär gespeichertes Formular. Bitte zuerst in Textform umwandeln, dann erneut umbenennen.';
     En: '%s is a form stored as binary. Please convert it to text form first, then rename again.'),
    (De: '"%s" ist kein gültiger Bezeichner.'; En: '"%s" is not a valid identifier.'),
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '),
    (De: 'Felder "textDocument.uri", "position" und "newName" fehlen in ';
     En: 'Fields "textDocument.uri", "position" and "newName" missing in '));

{$SCOPEDENUMS OFF}

function TokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

{ TLspRename }

function TLspRename.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspRename.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspRename.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
end;

constructor TLspRename.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
  FRenameHandlers := True;
end;

procedure TLspRename.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(PrepareMethod, HandlePrepare);
  ADispatcher.RegisterConcurrentRequest(RenameMethod, HandleRename);
end;

class function TLspRename.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prepareProvider', TJSONBool.Create(True));
end;

class function TLspRename.IsValidName(const AName: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(AName);
  // Genau ein Bezeichner ohne &-Escape; reservierte Wörter liefert der Lexer als Keyword.
  Result := (Length(Tokens) = 1) and (Tokens[0].Kind = TPascalTokenKind.Identifier) and
    (Tokens[0].Text = AName) and (AName[1] <> '&');
end;

class function TLspRename.Check(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; const AFiles: TArray<string>): TRenameCheck;
var
  Index: Integer;
  Targets: TArray<TDefinitionTarget>;
begin
  Result := Default(TRenameCheck);
  Index := TokenAt(ATree.Tokens, APosition);
  if Index < 0 then
  begin
    Result.Error := cTexts[TRenameText.ThereIsNoIdentifierHere].Text;
    Exit;
  end;
  Result.Range := TTextRange.Create(ATree.Tokens[Index].StartPos, ATree.Tokens[Index].EndPos);
  Result.Name := ATree.Tokens[Index].Text;
  if StartsStr('&', Result.Name) then
  begin
    Result.Name := Copy(Result.Name, 2, MaxInt);
  end;
  Targets := TLspDefinition.Targets(AResolver, AIndex, ATree, AFileName, APosition, True);
  if Length(Targets) > 0 then
  begin
    Result.DeclarationFile := Targets[0].FileName;
  end;
  if Length(Targets) = 0 then
  begin
    Result.Error := cTexts[TRenameText.IsNotKnown].Fmt([Result.Name]);
  end
  else if not SameText(Targets[0].FileName, AFileName) and (IndexText(Targets[0].FileName, AFiles) < 0) then
  begin
    Result.Error := cTexts[TRenameText.IsDeclaredOutsideTheProject].Fmt([Result.Name,
      ExtractFileName(Targets[0].FileName)]);
  end
  else if (Targets[0].Range.StartPos.Line = 0) and (Targets[0].Range.StartPos.Character = 0) and
    (Targets[0].Range.EndPos = Targets[0].Range.StartPos) then
  begin
    // Unit-Namen hängen am Dateinamen; das ist eine Dateioperation.
    Result.Error := cTexts[TRenameText.UnitsAreRenamedViaThe].Text;
  end;
end;

/// <summary>Gültigkeitsbereich eines unqualifiziert aufgelösten Namens: 1 lokal oder Parameter,
/// 2 Mitglied (Self oder with), 3 global; 0 = nicht aufgelöst.</summary>
function ScopeRank(const ASymbol: TResolvedSymbol): Integer;
begin
  case ASymbol.Kind of
    TResolvedKind.Local:
      Result := 1;
    TResolvedKind.Symbol:
      if ASymbol.Container <> '' then
      begin
        Result := 2;
      end
      else
      begin
        Result := 3;
      end;
  else
    Result := 0;
  end;
end;

function SameSymbol(const A, B: TResolvedSymbol): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Kind <> TResolvedKind.None) and SameText(A.Name, B.Name) and
    SameText(A.Container, B.Container) and SameText(A.FileName, B.FileName) and (A.SymbolKind = B.SymbolKind);
  // Routinen haben Deklaration und Rumpf; sonst entscheidet die Stelle.
  if Result and not (A.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine]) then
  begin
    Result := A.SelectionRange.StartPos = B.SelectionRange.StartPos;
  end;
end;

/// <summary>Gewinnt AWinner an derselben Stelle gegen ALoser? Gleicher Bereich zählt als Konflikt, außer
/// bei globalen Namen aus verschiedenen Units (dort entscheidet die uses-Reihenfolge wie bisher).</summary>
function Hides(const AWinner, ALoser: TResolvedSymbol): Boolean;
var
  Winner, Loser: Integer;
begin
  Winner := ScopeRank(AWinner);
  Loser := ScopeRank(ALoser);
  if (Winner = 0) or (Loser = 0) then
  begin
    Exit(False);
  end;
  if Winner <> Loser then
  begin
    Exit(Winner < Loser);
  end;
  Result := (Winner <> 3) or SameText(AWinner.FileName, ALoser.FileName);
end;

/// <summary>Bezeichner ohne Punkt davor (Self.Name, Liste.Name bleiben unberührt).</summary>
function IsUnqualified(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Before: Integer;
begin
  Before := AIndex - 1;
  while (Before >= 0) and (ATokens[Before].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Before);
  end;
  Result := (Before < 0) or not ATokens[Before].IsSymbol('.');
end;

function ConflictText(const AFileName: string; const AToken: TPascalToken; const ANewName: string;
  const AAfter, ABefore: TResolvedSymbol): string;
begin
  Result := cTexts[TRenameText.RenamingToWouldChangeThe].Fmt([ANewName, ExtractFileName(AFileName),
    AToken.StartPos.Line + 1, ANewName,
    AAfter.ShadowText, ABefore.ShadowText]);
end;

type
  /// <summary>Was die Konfliktprüfung je Datei braucht.</summary>
  TConflictScope = record
    Resolver: TNameResolver;
    /// <summary>Das umbenannte Symbol mit altem Namen.</summary>
    Renamed: TResolvedSymbol;
    OldName: string;
    NewName: string;
    Locations: TArray<TReferenceLocation>;
  end;

/// <summary>True, wenn AToken in AFile eine der umzubenennenden Stellen ist.</summary>
function IsLocation(const ALocations: TArray<TReferenceLocation>; const AFile: string;
  const AToken: TPascalToken): Boolean;
var
  mLocation: TReferenceLocation;
begin
  for mLocation in ALocations do
  begin
    if SameText(mLocation.FileName, AFile) and (mLocation.Range.StartPos = AToken.StartPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Konflikt am Bezeichner AToken in ATree; '' ohne.</summary>
function TokenConflict(const AScope: TConflictScope; ATree: TSyntaxTree; const AFile: string;
  const AToken: TPascalToken): string;
var
  mRenamed, mBefore, mAfter: TResolvedSymbol;
begin
  Result := '';
  if IsLocation(AScope.Locations, AFile, AToken) then
  begin
    // Umbenannte Stelle: Verdeckt dort ein anderer Name den neuen Namen des umbenannten Symbols?
    mAfter := AScope.Resolver.ResolveChain(ATree, AFile, [AScope.NewName], AToken.Offset, False);
    if Hides(mAfter, AScope.Renamed) then
    begin
      Result := ConflictText(AFile, AToken, AScope.NewName, mAfter, AScope.Renamed);
    end;
  end
  else if SameText(AToken.Text, AScope.NewName) or SameText(AToken.Text, '&' + AScope.NewName) then
  begin
    // Vorhandene Verwendung des neuen Namens: Sieht sie das umbenannte Symbol und läge es näher?
    mBefore := AScope.Resolver.ResolveChain(ATree, AFile, [AScope.NewName], AToken.Offset, False);
    mAfter := AScope.Resolver.ResolveChain(ATree, AFile, [AScope.OldName], AToken.Offset, False);
    if SameSymbol(mAfter, AScope.Renamed) and Hides(AScope.Renamed, mBefore) then
    begin
      mRenamed := AScope.Renamed;
      mRenamed.Name := AScope.NewName;
      Result := ConflictText(AFile, AToken, AScope.NewName, mRenamed, mBefore);
    end;
  end;
end;

/// <summary>Erster Konflikt in ATree der Datei AFile; '' ohne.</summary>
function TreeConflict(const AScope: TConflictScope; ATree: TSyntaxTree; const AFile: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ATree.Tokens) do
  begin
    if (ATree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and IsUnqualified(ATree.Tokens, mIndex) then
    begin
      Result := TokenConflict(AScope, ATree, AFile, ATree.Tokens[mIndex]);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Konflikt in den übrigen .pas-Dateien der Stellen; '' ohne.</summary>
function OtherFilesConflict(const AScope: TConflictScope; const AFileName: string;
  const AReadText: TReferenceReadText): string;
var
  mChecked: TArray<string>;
  mLocation: TReferenceLocation;
  mText: string;
  mTree: TSyntaxTree;
begin
  Result := '';
  mChecked := [AFileName];
  for mLocation in AScope.Locations do
  begin
    if (Result <> '') or not SameText(ExtractFileExt(mLocation.FileName), '.pas') or
      (IndexText(mLocation.FileName, mChecked) >= 0) then
    begin
      Continue;
    end;
    mChecked := mChecked + [mLocation.FileName];
    if Assigned(AReadText) and AReadText(mLocation.FileName, mText) then
    begin
      mTree := TSyntaxTreeCache.Parse(mText);
      try
        Result := TreeConflict(AScope, mTree, mLocation.FileName);
      finally
        mTree.Free;
      end;
    end;
  end;
end;

/// <summary>Das umbenannte Symbol: auf dem Namen einer Deklaration (Feld in der Klasse) löst Resolve nicht auf,
/// dann zählt eine Verwendung in derselben Datei.</summary>
function RenamedSymbol(AResolver: TNameResolver; ATree: TSyntaxTree; const ASearch: TReferenceSearch;
  const ALocations: TArray<TReferenceLocation>): TResolvedSymbol;
var
  mLocation: TReferenceLocation;
begin
  Result := AResolver.Resolve(ATree, ASearch.FileName, ASearch.Position);
  for mLocation in ALocations do
  begin
    if (Result.Kind = TResolvedKind.None) and SameText(mLocation.FileName, ASearch.FileName) then
    begin
      Result := AResolver.Resolve(ATree, ASearch.FileName, mLocation.Range.StartPos);
    end;
  end;
end;

class function TLspRename.Conflict(AResolver: TNameResolver; ATree: TSyntaxTree; const ASearch: TReferenceSearch;
  const ANewName: string; const ALocations: TArray<TReferenceLocation>): string;
var
  mScope: TConflictScope;
  mIndex: Integer;
begin
  Result := '';
  mIndex := TokenAt(ATree.Tokens, ASearch.Position);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mScope := Default(TConflictScope);
  mScope.Resolver := AResolver;
  mScope.NewName := ANewName;
  mScope.Locations := ALocations;
  mScope.OldName := ATree.Tokens[mIndex].Text;
  if StartsStr('&', mScope.OldName) then
  begin
    mScope.OldName := Copy(mScope.OldName, 2, MaxInt);
  end;
  // Nur die Schreibweise ändert sich: Delphi unterscheidet keine Groß- und Kleinschreibung.
  if SameText(mScope.OldName, ANewName) then
  begin
    Exit;
  end;
  mScope.Renamed := RenamedSymbol(AResolver, ATree, ASearch, ALocations);
  if mScope.Renamed.Kind in [TResolvedKind.None, TResolvedKind.UnitName] then
  begin
    Exit;
  end;
  Result := TreeConflict(mScope, ATree, ASearch.FileName);
  if Result = '' then
  begin
    Result := OtherFilesConflict(mScope, ASearch.FileName, ASearch.ReadText);
  end;
end;

function HasHandler(const ARenames: TArray<THandlerRename>; const AOldName: string): Boolean;
var
  Rename: THandlerRename;
begin
  for Rename in ARenames do
  begin
    if SameText(Rename.OldName, AOldName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Ein Umbenennen: Auflösung, Baum der Datei, Suche und Anfrage.</summary>
  TRenameScope = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    Search: TReferenceSearch;
    Request: TRenameRequest;
  end;

/// <summary>Umzubenennende Handler aus .dfm, .fmx und FMX-Plattformansichten (#87); jeder Handler nur einmal.</summary>
function FormHandlerRenames(const AChecked: TRenameCheck; const AUnitText, ANewName: string;
  const AReadText: TReferenceReadText): TArray<THandlerRename>;
var
  mFormFile, mFormText: string;
  mRename: THandlerRename;
begin
  Result := nil;
  for mFormFile in TFormFiles.FormFiles(AChecked.DeclarationFile, AUnitText) do
  begin
    if not AReadText(mFormFile, mFormText) then
    begin
      Continue;
    end;
    for mRename in TDfmComponentRename.Handlers(mFormText, AChecked.Name, ANewName) do
    begin
      if not HasHandler(Result, mRename.OldName) then
      begin
        Result := Result + [mRename];
      end;
    end;
  end;
end;

/// <summary>Methode ARename.OldName in ASymbols; False, wenn sie fehlt oder ein Handler mit dem neuen Namen
/// schon besteht (er würde doppelt deklariert).</summary>
function FindHandler(const ASymbols: TArray<TIndexSymbol>; const ARename: THandlerRename;
  out AHandler: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mFound: Boolean;
begin
  AHandler := Default(TIndexSymbol);
  mFound := False;
  for mSymbol in ASymbols do
  begin
    if mSymbol.Kind <> TIndexSymbolKind.Method then
    begin
      Continue;
    end;
    if SameText(mSymbol.Name, ARename.OldName) and not mFound then
    begin
      AHandler := mSymbol;
      mFound := True;
    end
    else if SameText(mSymbol.Name, ARename.NewName) then
    begin
      Exit(False);
    end;
  end;
  Result := mFound;
end;

/// <summary>Stellen der Handler ARenames im Baum ATree der Datei AFileName.</summary>
function HandlerLocations(const AScope: TRenameScope; ATree: TSyntaxTree; const AFileName: string;
  const ARenames: TArray<THandlerRename>): TArray<TRenameEdit>;
var
  mSymbols: TArray<TIndexSymbol>;
  mHandler: TIndexSymbol;
  mRename: THandlerRename;
  mLocation: TReferenceLocation;
  mEdit: TRenameEdit;
begin
  Result := nil;
  mSymbols := TIndexExtractor.Extract(ATree, AFileName).Symbols;
  for mRename in ARenames do
  begin
    if not FindHandler(mSymbols, mRename, mHandler) then
    begin
      Continue;
    end;
    for mLocation in TLspReferences.Find(AScope.Resolver, AScope.Index, ATree, TReferenceSearch.Create(AFileName,
      mHandler.SelectionRange.StartPos, True, AScope.Search.Files, AScope.Search.ReadText),
      AScope.Request.Cancellation) do
    begin
      mEdit.FileName := mLocation.FileName;
      mEdit.Range := mLocation.Range;
      mEdit.NewText := mRename.NewName;
      Result := Result + [mEdit];
    end;
  end;
end;

/// <summary>Umbenennen der Handler einer umbenannten Komponente (#45).</summary>
function HandlerEdits(const AScope: TRenameScope; const AChecked: TRenameCheck): TArray<TRenameEdit>;
var
  mUnitText: string;
  mRenames: TArray<THandlerRename>;
  mTree: TSyntaxTree;
begin
  Result := nil;
  if (AChecked.DeclarationFile = '') or not AScope.Search.ReadText(AChecked.DeclarationFile, mUnitText) then
  begin
    Exit;
  end;
  mRenames := FormHandlerRenames(AChecked, mUnitText, AScope.Request.NewName, AScope.Search.ReadText);
  if Length(mRenames) = 0 then
  begin
    Exit;
  end;
  // Die Handler stehen in der Unit des Formulars.
  if SameText(AChecked.DeclarationFile, AScope.Search.FileName) then
  begin
    Exit(HandlerLocations(AScope, AScope.Tree, AChecked.DeclarationFile, mRenames));
  end;
  mTree := TSyntaxTreeCache.Parse(mUnitText);
  try
    Result := HandlerLocations(AScope, mTree, AChecked.DeclarationFile, mRenames);
  finally
    mTree.Free;
  end;
end;

/// <summary>Teilt AFound in umzubenennende Stellen (Ergebnis) und erschlossene, die bleiben (AUnchanged).</summary>
function RenameableOf(const AFound: TArray<TReferenceLocation>;
  out AUnchanged: TArray<TReferenceLocation>): TArray<TReferenceLocation>;
var
  mLocation: TReferenceLocation;
begin
  Result := nil;
  AUnchanged := nil;
  for mLocation in AFound do
  begin
    if mLocation.Confidence.Renameable then
    begin
      Result := Result + [mLocation];
    end
    else
    begin
      AUnchanged := AUnchanged + [mLocation];
    end;
  end;
end;

/// <summary>Ersetzungen von ALocations durch ANewName.</summary>
function LocationEdits(const ALocations: TArray<TReferenceLocation>; const ANewName: string): TArray<TRenameEdit>;
var
  mLocation: TReferenceLocation;
  mEdit: TRenameEdit;
begin
  Result := nil;
  for mLocation in ALocations do
  begin
    mEdit.FileName := mLocation.FileName;
    mEdit.Range := mLocation.Range;
    mEdit.NewText := ANewName;
    Result := Result + [mEdit];
  end;
end;

/// <summary>Ersetzungen des Typnamens in den Typkommentaren über den Rümpfen des umbenannten Typs (#1838); ohne
/// solche Kommentare (auch bei Nicht-Typen) keine.</summary>
function TypeCommentEdits(const AScope: TRenameScope; const AChecked: TRenameCheck): TArray<TRenameEdit>;
var
  mText: string;
  mSpot: TTypeNameSpot;
  mEdit: TRenameEdit;
begin
  Result := nil;
  if not AScope.Request.TypeComments or not SameText(ExtractFileExt(AChecked.DeclarationFile), '.pas') or
    not Assigned(AScope.Search.ReadText) or
    not AScope.Search.ReadText(AChecked.DeclarationFile, mText) then
  begin
    Exit;
  end;
  for mSpot in TTypeComments.NameSpots(TTextLines.SplitLines(mText), AChecked.Name) do
  begin
    mEdit.FileName := AChecked.DeclarationFile;
    mEdit.Range := TTextRange.Create(mSpot.Line, mSpot.Character, mSpot.Line,
      mSpot.Character + Length(AChecked.Name));
    mEdit.NewText := AScope.Request.NewName;
    Result := Result + [mEdit];
  end;
end;

/// <summary>EJsonRpcError, wenn eine Ersetzung ein binär gespeichertes Formular trifft (#121).</summary>
procedure CheckTextForms(const AEdits: TArray<TRenameEdit>);
var
  mEdit: TRenameEdit;
begin
  for mEdit in AEdits do
  begin
    if not SameText(ExtractFileExt(mEdit.FileName), '.pas') and TFileEncoding.IsBinaryFormFile(mEdit.FileName) then
    begin
      raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, cTexts[TRenameText.IsAFormStoredAs].Fmt([
        ExtractFileName(mEdit.FileName)]));
    end;
  end;
end;

{ TRenameRequest }

class function TRenameRequest.Create(const ANewName: string): TRenameRequest;
begin
  Result := Create(ANewName, True, TReferenceSettings.SureOnly, nil);
end;

class function TRenameRequest.Create(const ANewName: string; ARenameHandlers: Boolean;
  const ASettings: TReferenceSettings; const ACancellation: IJsonRpcCancellationToken): TRenameRequest;
begin
  Result := Default(TRenameRequest);
  Result.NewName := ANewName;
  Result.RenameHandlers := ARenameHandlers;
  Result.Settings := ASettings;
  Result.Cancellation := ACancellation;
  Result.TypeComments := True;
end;

class function TLspRename.Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch; const ANewName: string): TArray<TRenameEdit>;
begin
  Result := Edits(AResolver, AIndex, ATree, ASearch, TRenameRequest.Create(ANewName));
end;

class function TLspRename.Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch; const ARequest: TRenameRequest): TArray<TRenameEdit>;
var
  mUnchanged: TArray<TReferenceLocation>;
begin
  Result := Edits(AResolver, AIndex, ATree, ASearch, ARequest, mUnchanged);
end;

class function TLspRename.Edits(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ASearch: TReferenceSearch; const ARequest: TRenameRequest;
  out AUnchanged: TArray<TReferenceLocation>): TArray<TRenameEdit>;
var
  mScope: TRenameScope;
  mChecked: TRenameCheck;
  mLocations: TArray<TReferenceLocation>;
  mReason: string;
begin
  AUnchanged := nil;
  if not IsValidName(ARequest.NewName) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, cTexts[TRenameText.IsNotAValidIdentifier].Fmt([
      ARequest.NewName]));
  end;
  mChecked := Check(AResolver, AIndex, ATree, ASearch.FileName, ASearch.Position, ASearch.Files);
  if mChecked.Error <> '' then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, mChecked.Error);
  end;
  mScope.Resolver := AResolver;
  mScope.Index := AIndex;
  mScope.Tree := ATree;
  mScope.Search := ASearch;
  mScope.Search.Declaration := True;
  mScope.Request := ARequest;
  mLocations := RenameableOf(TLspReferences.Find(AResolver, AIndex, ATree, mScope.Search, ARequest.Settings,
    ARequest.Cancellation), AUnchanged);
  mReason := Conflict(AResolver, ATree, mScope.Search, ARequest.NewName, mLocations);
  if mReason <> '' then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, mReason);
  end;
  Result := LocationEdits(mLocations, ARequest.NewName) + TypeCommentEdits(mScope, mChecked);
  if ARequest.RenameHandlers and Assigned(ASearch.ReadText) then
  begin
    Result := Result + HandlerEdits(mScope, mChecked);
  end;
  CheckTextForms(Result);
end;

function TLspRename.ProjectFiles: TArray<string>;
begin
  if Assigned(FFiles) then
  begin
    Result := FFiles();
  end
  else
  begin
    Result := nil;
  end;
end;

function TLspRename.HandlePrepare(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Checked: TRenameCheck;
  Files: TArray<string>;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TRenameText.FieldsTextDocumentUriAndPosition].Text + PrepareMethod);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  Files := ProjectFiles;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Checked := Check(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
      Files);
  finally
    Resolver.Free;
  end;
  // Der Editor zeigt die Fehlermeldung an.
  if Checked.Error <> '' then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, Checked.Error);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('range', TLspPositions.RangeToJson(Checked.Range));
  TJSONObject(Result).AddPair('placeholder', Checked.Name);
end;

/// <summary>Ersetzungen je Datei als "changes" einer WorkspaceEdit.</summary>
function ChangesJson(const AEdits: TArray<TRenameEdit>): TJSONObject;
var
  mEdit: TRenameEdit;
  mUri: string;
  mList: TJSONArray;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    for mEdit in AEdits do
    begin
      mUri := TDocumentUris.FromPath(mEdit.FileName);
      mList := Result.GetValue(mUri) as TJSONArray;
      if mList = nil then
      begin
        mList := TJSONArray.Create;
        Result.AddPair(mUri, mList);
      end;
      mItem := TJSONObject.Create;
      mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
      mItem.AddPair('newText', mEdit.NewText);
      mList.AddElement(mItem);
    end;
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Erschlossene Stellen, die nicht geändert werden (Erweiterung atlasUnchanged, #1119).</summary>
function UnchangedJson(const AUnchanged: TArray<TReferenceLocation>): TJSONArray;
var
  mLocation: TReferenceLocation;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mLocation in AUnchanged do
  begin
    mItem := TJSONObject.Create;
    Result.AddElement(mItem);
    mItem.AddPair('uri', TDocumentUris.FromPath(mLocation.FileName));
    mItem.AddPair('range', TLspPositions.RangeToJson(mLocation.Range));
    mItem.AddPair('atlasConfidence', mLocation.Confidence.ToJson);
  end;
end;

function TLspRename.SettingsOf(const AUri: string): TReferenceSettings;
begin
  if Assigned(FSettingsFor) then
  begin
    Result := FSettingsFor(AUri);
  end
  else
  begin
    Result := TReferenceSettings.Default;
  end;
end;

function TLspRename.HandleRename(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mNewName: string;
  mPosition: TJSONValue;
  mDocument: ITextDocument;
  mCancellation: IPascalCancellation;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mFound: TArray<TRenameEdit>;
  mUnchanged: TArray<TReferenceLocation>;
  mRequest: TRenameRequest;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPosition) and
    TJSONObject(AParams).TryGetValue<string>('newName', mNewName)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TRenameText.FieldsTextDocumentUriPositionAnd].Text + RenameMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  // In einer Variablen: Als const-Argument würde das Objekt nie gezählt und bliebe liegen.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    mRequest := TRenameRequest.Create(Trim(mNewName), FRenameHandlers, SettingsOf(mUri), ACancellation);
    mRequest.TypeComments := not Assigned(FTypeCommentsFor) or FTypeCommentsFor(mUri);
    mFound := Edits(mResolver, FIndex, mShared.Tree, TReferenceSearch.Create(TDocumentUris.ToPath(mUri),
      TLspPositions.ReadPosition(mPosition), True, ProjectFiles, FReadText), mRequest, mUnchanged);
  finally
    mResolver.Free;
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('changes', ChangesJson(mFound));
  // Editoren ohne Kenntnis der Erweiterung übergehen atlasUnchanged.
  if Length(mUnchanged) > 0 then
  begin
    TJSONObject(Result).AddPair('atlasUnchanged', UnchangedJson(mUnchanged));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Rename', cTexts);

end.
