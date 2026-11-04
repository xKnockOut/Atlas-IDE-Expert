unit Atlas.Common.Editing.GenericLists;

// Ungenerische Listen in generische umwandeln (#1105 legacy-tlist, #1106 Stapel
// und Warteschlangen): TList → TList<T>, TObjectList (Contnrs) →
// TObjectList<T>, TStack/TQueue/TObjectStack/TObjectQueue → die Gegenstücke
// aus System.Generics.Collections. Was eine Listenart kann, beschreibt
// TLegacyListKind (.Kinds); die Regeln geben nur die Art und die Deklaration herein.
// TGenericListConversion ist die oberste Stufe der Klassenkette State →
// Declarations → Usages (eigene Units GenericLists.*); uses-Listen schreibt
// .UsesEdits, die Edits je Datei sammelt .Source.
//
// - Elementtyp T: Alle Lesezugriffe (L[I], L.Items[I], First, Last, Pop, Peek,
//   Extract, for … in) müssen denselben Cast haben, T(L[I]) oder L[I] as T.
//   Lesen ohne Cast ist nur erlaubt, wo der genauere Typ nichts ändert:
//   Vergleich mit nil, Assigned, Zuweisung an einen Pointer und bei
//   Objektlisten Free und andere TObject-Mitglieder.
// - Umgeschrieben werden die Deklaration (bei "A, B: TList" wird L
//   abgespalten), jedes Create (Argumente bleiben; bei TObjectStack/-Queue,
//   deren generische Klassen ihre Objekte besitzen, Create(False)), die Casts,
//   umbenannte Methoden (Push → Enqueue …), Schleifenvariablen von for … in
//   (Typ Pointer → T) und eine Property, die das Feld direkt liest
//   (property Items: TList read FItems). System.Generics.Collections kommt in
//   das uses des Abschnitts, in dem der generische Typ steht; Contnrs entfällt,
//   wenn die Unit danach keinen Typ daraus mehr nennt.
// - Keine Umwandlung (Grund in Reason): Methoden ohne Gegenstück (Sort mit
//   TListSortCompare, Assign mit TListAssignOp, List, Expand, Pack …),
//   Elemente als Pointer oder Ganzzahl (Add(Pointer(…)), Integer(L[I])),
//   Argumente von Add/Insert/Extract/Remove/IndexOf mit anderem Typ als T,
//   Weitergabe der Liste (an Parameter, Result, andere Variablen, with),
//   Erzeugen mit einer anderen Klasse, Properties mit Getter, Parameter und
//   Funktionsergebnisse vom alten Typ. Ist die Liste außerhalb der Unit
//   sichtbar (Feld oder Property nicht privat, globale Variable im
//   interface), nennt ExternalNames die Namen; der Aufrufer gibt die Units,
//   die einen davon enthalten, über AddFile herein. Deren Stellen werden nach
//   denselben Regeln umgeschrieben oder verhindern die Umwandlung.
// - Safe: Alle Argumente haben einen bekannten, passenden Typ, und nur die
//   eigene Datei ändert sich. Sonst bietet die Regel die Korrektur nur als
//   Code-Aktion an, nicht in source.fixAll.


interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.GenericLists.Usages;

type
  /// <summary>Ergebnis der Umwandlung.</summary>
  TGenericListPlan = record
    /// <summary>Titel der Code-Aktion, z. B. "In TList&lt;TPosition&gt; umwandeln".</summary>
    Title: string;
    /// <summary>Elementtyp, wie ihn der erste Cast schreibt.</summary>
    ItemType: string;
    /// <summary>Edits der Datei mit der Deklaration.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Units; nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    /// <summary>Ohne Rückfrage anwendbar (source.fixAll): alle Typen bekannt, nur diese Datei.</summary>
    Safe: Boolean;
  end;

  /// <summary>Wandelt eine ungenerische Liste um. Ablauf: Start mit der Deklaration, für ExternalNames weitere
  /// Units über AddFile, dann Finish. Nach einem Fehlschlag nennt Reason den Grund.</summary>
  TGenericListConversion = class(TGenericListUsages)
  private
    function DistinctCastTypes: TArray<string>;
    function CheckCasts: Boolean;
    function CheckElements: Boolean;
    function CheckCreated: Boolean;
    function CheckItems: Boolean;
    function CheckItemTypeKnown: Boolean;
    function PrepareFile(AFileIndex: Integer): Boolean;
    function PrepareFiles: Boolean;
    function BuildPlan: TGenericListPlan;
  public
    /// <summary>ADeclaration ist der Field-, VarDecl- oder InlineVar-Knoten der Liste AName in ATree (gehört dem
    /// Aufrufer und muss bis Finish leben). False mit Reason, wenn die Umwandlung schon hier ausscheidet.</summary>
    function Start(ATree: TSyntaxTree; const AText, AFileName: string; ADeclaration: TSyntaxNode;
      const AName: string): Boolean;
    /// <summary>Namen, unter denen andere Units die Liste erreichen (Feld bzw. Variable und Properties); leer,
    /// wenn sie nur in dieser Unit sichtbar ist.</summary>
    function ExternalNames: TArray<string>;
    /// <summary>Weitere Unit, die einen der ExternalNames enthält; wird hier geparst.</summary>
    procedure AddFile(const AText, AFileName: string);
    /// <summary>Die Umwandlung ist nicht möglich, z. B. weil eine Unit nicht lesbar ist.</summary>
    procedure Reject(const AReason: string);
    /// <summary>Elementtyp bestimmen, Argumente prüfen, uses ergänzen. False mit Reason.</summary>
    function Finish(out APlan: TGenericListPlan): Boolean;
    /// <summary>Grund, warum die Umwandlung nicht angeboten wird; '' solange möglich.</summary>
    property Reason: string read FReason;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Editing.GenericLists.Source,
  Atlas.Common.Editing.GenericLists.State,
  Atlas.Common.Editing.GenericLists.Elements,
  Atlas.Common.Editing.GenericLists.UsesEdits;

{ TGenericListConversion }

function TGenericListConversion.Start(ATree: TSyntaxTree; const AText, AFileName: string;
  ADeclaration: TSyntaxNode; const AName: string): Boolean;
begin
  AddSource(ATree, False, AText, AFileName);
  FTarget.Declaration := ADeclaration;
  FTarget.DeclarationLine := ADeclaration.StartPos.Line;
  FTarget.Name := AName;
  FTarget.UnitName := TUsesClauses.OwnName(ATree.Tokens);
  ScanDeclaration(FFiles[0]);
  if not Failed then
  begin
    CollectUses(0);
  end;
  Result := not Failed;
end;

function TGenericListConversion.ExternalNames: TArray<string>;
begin
  Result := FExternalNames;
end;

procedure TGenericListConversion.AddFile(const AText, AFileName: string);
begin
  if not Failed then
  begin
    CollectUses(AddSource(TSyntaxTreeCache.Parse(AText), True, AText, AFileName));
  end;
end;

procedure TGenericListConversion.Reject(const AReason: string);
begin
  Fail(AReason);
end;

function TGenericListConversion.DistinctCastTypes: TArray<string>;
var
  mCast: TGenericListCast;
  mName: string;
begin
  Result := nil;
  for mCast in FCasts do
  begin
    mName := TGenericListSyntax.LastName(mCast.TypeText);
    if not MatchText(mName, Result) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function TGenericListConversion.CheckCasts: Boolean;
var
  mDistinct: TArray<string>;
  mItemName: string;
begin
  mDistinct := DistinctCastTypes;
  mItemName := TGenericListSyntax.LastName(ItemType);
  if FCasts = nil then
  begin
    Result := Fail(Format('%s wird nirgends mit Cast gelesen; der Elementtyp ist unbekannt', [FTarget.Name]));
  end
  else if Length(mDistinct) > 1 then
  begin
    Result := Fail(Format('%s wird mit verschiedenen Casts gelesen: %s', [FTarget.Name,
      string.Join(', ', mDistinct)]));
  end
  else if TGenericListNames.IsScalarType(mItemName) then
  begin
    Result := Fail(Format('%s enthält Werte vom Typ %s statt Objekte', [FTarget.Name, mItemName]));
  end
  else
  begin
    Result := True;
  end;
end;

function TGenericListConversion.CheckElements: Boolean;
var
  mElement: TGenericListElement;
  mCheck: TGenericListElementCheck;
  mFit: TGenericListElementFit;
begin
  mCheck := TGenericListElementCheck.Create(FResolver, FFiles, FTarget.Name, ItemType);
  for mElement in FElements do
  begin
    mFit := mCheck.Check(mElement);
    if mFit = TGenericListElementFit.Wrong then
    begin
      Exit(Fail(mCheck.Problem));
    end;
    FUnknown := FUnknown or (mFit = TGenericListElementFit.Unknown);
  end;
  Result := True;
end;

function TGenericListConversion.CheckCreated: Boolean;
begin
  Result := (FKind.CreateArguments = '') or FCreated or
    Fail(Format('%s wird hier nicht erzeugt; ohne Create lässt sich nicht festlegen, dass %s<T> die Objekte ' +
    'nicht besitzt', [FTarget.Name, FKind.GenericName]));
end;

function TGenericListConversion.CheckItems: Boolean;
begin
  Result := CheckCasts and CheckElements and CheckCreated;
end;

function TGenericListConversion.CheckItemTypeKnown: Boolean;
var
  mIndex: Integer;
  mSource: TGenericListSource;
begin
  // Der neue Typtext nennt T: In weiteren Units, in denen er steht, muss T bekannt sein.
  for mIndex := 1 to FFiles.Count - 1 do
  begin
    mSource := FFiles[mIndex];
    if (mSource.GenericAt <> nil) and not mSource.MentionsIdentifier(TGenericListSyntax.LastName(ItemType)) then
    begin
      Exit(Fail(Format('%s ist in %s nicht bekannt', [ItemType, ExtractFileName(mSource.FileName)])));
    end;
  end;
  Result := True;
end;

function TGenericListConversion.PrepareFile(AFileIndex: Integer): Boolean;
var
  mSource: TGenericListSource;
  mReason: string;
begin
  mSource := FFiles[AFileIndex];
  if ((mSource.GenericAt <> nil) or (mSource.Rewritten <> nil)) and
    not TGenericListUses.AddEdits(mSource, FKind, FResolver.Namespaces, mReason) then
  begin
    Exit(Fail(mReason));
  end;
  Result := mSource.Finalize(GenericText, ItemType, mReason) or Fail(mReason);
end;

function TGenericListConversion.PrepareFiles: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FFiles.Count - 1 do
  begin
    if not PrepareFile(mIndex) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TGenericListConversion.BuildPlan: TGenericListPlan;
var
  mIndex: Integer;
  mFileEdits: TFileTextEdits;
begin
  Result := Default(TGenericListPlan);
  Result.Title := Format('In %s umwandeln', [GenericText]);
  Result.ItemType := ItemType;
  Result.Edits := FFiles[0].Edits;
  for mIndex := 1 to FFiles.Count - 1 do
  begin
    if FFiles[mIndex].Edits <> nil then
    begin
      mFileEdits.FileName := FFiles[mIndex].FileName;
      mFileEdits.Edits := FFiles[mIndex].Edits;
      Result.FileEdits := Result.FileEdits + [mFileEdits];
    end;
  end;
  Result.Safe := not FUnknown and (Result.FileEdits = nil);
end;

function TGenericListConversion.Finish(out APlan: TGenericListPlan): Boolean;
begin
  APlan := Default(TGenericListPlan);
  Result := not Failed and CheckItems and CheckItemTypeKnown and PrepareFiles;
  if Result then
  begin
    APlan := BuildPlan;
  end;
end;

end.
