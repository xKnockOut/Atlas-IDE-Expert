unit Atlas.Common.Lsp.Hover.Lookup;

// Sammelt den Inhalt eines Hovers (THoverInfo) an einer Stelle.
//
// Die Deklaration ist die erste Zeile der Fundstelle ab ihrem Anfang. Der
// Dokumentationskommentar sind die ///-Zeilen direkt darüber, zerlegt von
// TXmlDoc samt <inheritdoc/> (TLspDocumentation, #654). Bei Methoden mit
// getrennter Implementierung gilt die Deklaration (TLspDefinition).
// Bei Klassen folgen die published-Properties und Ereignisse samt geerbter
// (TPublishedMembers). Auf einem Attribut (#119) zusätzlich die Konstruktoren
// der Attributklasse, bei Argumenten die mit passender Parameterzahl.
// Zahlenliterale zeigen ihre Schreibweisen, Bezeichner von System ohne
// Quelltext die eingebaute Beschreibung (#880), Unit-Namen den Dateinamen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.Hover.Info;

type
  TLspHoverLookup = class
  public
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree, ADelphiVersion der Release-Name für
    /// die DocWiki-Links ('' = neueste).</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Files,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Semantics.Attributes,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormInfo,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.DocWiki,
  Atlas.Common.Lsp.WinApiDocs,
  Atlas.Common.Lsp.MessageHandlers,
  Atlas.Common.Lsp.HoverValues,
  Atlas.Common.Lsp.HoverTypes,
  Atlas.Common.Lsp.PublishedMembers,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLookupText = (PossibleElement, PossibleElements);

const
  cTexts: array[TLookupText] of TAtlasText = (
    (De: ' · 1 mögliches Element'; En: ' · 1 possible element'),
    (De: ' · %s mögliche Elemente'; En: ' · %s possible elements'));

{$SCOPEDENUMS OFF}

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

/// <summary>Deklaration von ARange bis zum Ende der letzten Zeile (dort stehen Direktiven wie deprecated).</summary>
function DeclarationText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
end;

/// <summary>Ordinalzahl eines Aufzählungswerts: Position im Typ, ohne explizite Werte.</summary>
function EnumOrdinal(const AUnit: TUnitIndex; const AMember: TIndexSymbol): Integer;
var
  mSymbol: TIndexSymbol;
begin
  Result := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AMember.Container) then
    begin
      if mSymbol.SelectionRange.StartPos = AMember.SelectionRange.StartPos then
      begin
        Exit;
      end;
      Inc(Result);
    end;
  end;
end;

/// <summary>Zahl der Werte der Aufzählung ABaseType laut Index; -1, wenn sie sich nicht auflösen lässt.</summary>
function EnumMemberCount(AResolver: TNameResolver; const AUnit: TUnitIndex; const ABaseType: string): Integer;
var
  mResolved: TResolvedSymbol;
  mEnumUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := -1;
  if not (AResolver.ResolveTypeFrom(AUnit, ABaseType, mResolved) and
    (mResolved.SymbolKind = TIndexSymbolKind.EnumType) and AResolver.DeclaringUnit(mResolved, mEnumUnit)) then
  begin
    Exit;
  end;
  Result := 0;
  for mSymbol in mEnumUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, mResolved.Name) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Bei Mengentypen "set of TBar · 4 mögliche Elemente" (#38); Aufzählungen über den Index gezählt.
/// '' bei anderen Typen.</summary>
function SetTypeValue(AResolver: TNameResolver; const AUnit: TUnitIndex; const ADeclaration: string): string;
var
  mBaseType: string;
  mCount: Integer;
begin
  Result := '';
  if not THoverValues.SetBaseType(ADeclaration, mBaseType) then
  begin
    Exit;
  end;
  mCount := THoverValues.BaseTypeCount(mBaseType);
  if mCount < 0 then
  begin
    mCount := EnumMemberCount(AResolver, AUnit, mBaseType);
  end;
  Result := 'set of ' + mBaseType;
  if mCount = 1 then
  begin
    Result := Result + cTexts[TLookupText.PossibleElement].Text;
  end
  else if mCount >= 0 then
  begin
    Result := Result + cTexts[TLookupText.PossibleElements].Fmt([IntToStr(mCount)]);
  end;
end;

/// <summary>Text der Formulardatei neben AUnitFile (.dfm vor .fmx); die geöffnete Datei AOpenFile aus AOpenText.
/// '' ohne Formulardatei.</summary>
function FormText(const AUnitFile, AOpenFile, AOpenText: string; const AReadText: TDocReadText;
  out AFormFile: string): string;
var
  mExtension: string;
begin
  Result := '';
  for mExtension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    AFormFile := ChangeFileExt(AUnitFile, mExtension);
    if SameText(AFormFile, AOpenFile) then
    begin
      Result := AOpenText;
    end
    else if not (Assigned(AReadText) and AReadText(AFormFile, Result)) then
    begin
      Result := '';
    end;
    if Result <> '' then
    begin
      Break;
    end;
  end;
end;

/// <summary>Werte des Komponentenfelds AFieldName im Formular AFormText (#126); nur die eigene Formulardatei, ohne
/// Vorfahr-Formulare (#115 nicht geplant).</summary>
function FormFieldValues(const AFormText, AFormFile, AFormClass, AFieldName: string): string;
var
  mDocument: TDfmDocument;
  mObject: TDfmObject;
begin
  Result := '';
  if AFormText = '' then
  begin
    Exit;
  end;
  mDocument := TDfmParser.Parse(AFormText);
  try
    mObject := TFormInfo.FindComponent(mDocument, AFormClass, AFieldName);
    if mObject <> nil then
    begin
      Result := TFormInfo.ComponentMarkdown(mObject, AFormFile);
    end;
  finally
    mDocument.Free;
  end;
end;

/// <summary>Konstruktor ASymbol steht in der Deklaration der Klasse AClass (Zeilen dazwischen).</summary>
function IsOwnConstructor(const ASymbol, AClass: TIndexSymbol; const ALines: TArray<string>): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(ASymbol.Container, AClass.Name) and
    (ASymbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
    (ASymbol.Range.StartPos.Line < AClass.Range.EndPos.Line) and (ASymbol.Range.StartPos.Line <= High(ALines));
end;

/// <summary>Konstruktoren von AClass in AUnit, die AArgCount Argumente annehmen; passt keiner, alle.</summary>
function AttributeConstructors(const AUnit: TUnitIndex; const AClass: TIndexSymbol; const ALines: TArray<string>;
  AArgCount: Integer): string;
var
  mSymbol: TIndexSymbol;
  mAll, mMatching, mLine: string;
begin
  mAll := '';
  mMatching := '';
  for mSymbol in AUnit.Symbols do
  begin
    if IsOwnConstructor(mSymbol, AClass, ALines) then
    begin
      mLine := Trim(ALines[mSymbol.Range.StartPos.Line]);
      mAll := mAll + IfThen(mAll <> '', #10) + mLine;
      if (AArgCount >= mSymbol.MinArgs) and (AArgCount <= mSymbol.MaxArgs) then
      begin
        mMatching := mMatching + IfThen(mMatching <> '', #10) + mLine;
      end;
    end;
  end;
  Result := IfThen(mMatching <> '', mMatching, mAll);
end;

/// <summary>Leser für TPublishedMembers: die eigene Datei kommt aus dem Editor, nicht von der Platte. Eigene
/// Routine, damit die anonyme Methode nur diese Kopien einfängt.</summary>
function MemberReader(const AFileName, ATreeText: string; const AReadText: TDocReadText): TMemberReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      Result := SameText(AName, AFileName);
      if Result then
      begin
        AText := ATreeText;
      end
      else
      begin
        Result := Assigned(AReadText) and AReadText(AName, AText);
      end;
    end;
end;

/// <summary>Derselbe Leser für TMessageHandlers.</summary>
function MessageReader(const AFileName, ATreeText: string; const AReadText: TDocReadText): TMessageReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      Result := SameText(AName, AFileName);
      if Result then
      begin
        AText := ATreeText;
      end
      else
      begin
        Result := Assigned(AReadText) and AReadText(AName, AText);
      end;
    end;
end;

type
  /// <summary>Ein Hover-Lauf: Felder statt Locals, Schritte als Methoden.</summary>
  THoverLookupRun = class
  private
    FSource: THoverSource;
    FTree: TSyntaxTree;
    FTreeText: string;
    FFileName: string;
    FPosition: TTextPosition;
    FDelphiVersion: string;
    FInfo: THoverInfo;
    /// <summary>Erstes Ziel der Definition.</summary>
    FTarget: TDefinitionTarget;
    /// <summary>Text und Zeilen der Datei des Ziels.</summary>
    FText: string;
    FLines: TArray<string>;
    FOwner: TUnitIndex;
    FSelfName: string;
    FTypeSymbol: Boolean;
    FDocSymbol: TResolvedSymbol;
    FDocContainer: string;
    function TryNumber: Boolean;
    function TryIntrinsic: Boolean;
    function FindTarget: Boolean;
    function TryUnitName: Boolean;
    function ReadDeclaration: Boolean;
    function FindOwnerUnit: Boolean;
    function IsTargetSymbol(const ASymbol: TIndexSymbol): Boolean;
    function ValueOf(const ASymbol: TIndexSymbol): string;
    procedure ApplySymbol(const ASymbol: TIndexSymbol);
    procedure ApplyDocumentation;
    procedure ApplyTypes;
    function IsTargetClass(const ASymbol: TIndexSymbol): Boolean;
    function MessagesOf(const AClassName: string): string;
    procedure ApplyClass(const ASymbol: TIndexSymbol);
  public
    constructor Create(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition);
    function Run(const ADelphiVersion: string): THoverInfo;
  end;

constructor THoverLookupRun.Create(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition);
begin
  inherited Create;
  FSource := ASource;
  FTree := ATree;
  FTreeText := ATreeText;
  FFileName := AFileName;
  FPosition := APosition;
end;

function THoverLookupRun.TryNumber: Boolean;
var
  mToken: TPascalToken;
  mNumber: Int64;
begin
  // Zahlenliteral unter dem Cursor: Schreibweisen statt Deklaration.
  Result := False;
  for mToken in FTree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Number) and (ComparePositions(mToken.StartPos, FPosition) <= 0) and
      (ComparePositions(FPosition, mToken.EndPos) < 0) then
    begin
      if THoverValues.TryParseNumber(mToken.Text, mNumber) then
      begin
        FInfo.Declaration := mToken.Text;
        FInfo.Value := THoverValues.FormatNumber(mNumber);
      end
      else
      begin
        TRequestDiagnostics.Reason('numberUnparsed');
      end;
      Exit(True);
    end;
  end;
end;

function THoverLookupRun.TryIntrinsic: Boolean;
var
  mName: string;
  mIntrinsic: TSystemIntrinsic;
begin
  // Bezeichner von System ohne Quelltext (#880): Kopf und Beschreibung aus der eingebauten Liste.
  Result := TSystemIntrinsics.NameAt(FTree, FPosition, mName);
  if not Result then
  begin
    Exit;
  end;
  for mIntrinsic in TSystemIntrinsics.Find(mName) do
  begin
    if FInfo.Declaration <> '' then
    begin
      FInfo.Declaration := FInfo.Declaration + #10;
    end;
    FInfo.Declaration := FInfo.Declaration + mIntrinsic.Declaration;
    if FInfo.Documentation = '' then
    begin
      FInfo.Documentation := mIntrinsic.Documentation;
    end;
  end;
  FInfo.UnitName := 'System';
end;

function THoverLookupRun.FindTarget: Boolean;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TLspDefinition.Targets(FSource.Resolver, FSource.Index, FTree, FFileName, FPosition, True);
  Result := Length(mTargets) > 0;
  if Result then
  begin
    FTarget := mTargets[0];
  end
  else if not TryIntrinsic then
  begin
    // Grundcodes für das Diagnoselog (#647).
    TRequestDiagnostics.Reason('noTarget');
  end;
end;

function THoverLookupRun.TryUnitName: Boolean;
var
  mUnit: TUnitIndex;
begin
  // Unit-Namen: Ziel ist der Dateianfang. Vor dem Lesen der Datei prüfen, denn dafür wird ihr Text nicht gebraucht.
  Result := (FTarget.Range.StartPos = TTextPosition.Create(0, 0)) and (FTarget.Range.EndPos = FTarget.Range.StartPos)
    and not SameText(FTarget.FileName, FFileName);
  if not Result then
  begin
    Exit;
  end;
  if FSource.Index.FindFile(FTarget.FileName, mUnit) then
  begin
    FInfo.Declaration := 'unit ' + mUnit.UnitName + ';';
    FInfo.DocWikiUrl := TDocWiki.Url(FDelphiVersion, mUnit.UnitName, '', '');
    FInfo.Rationale := TRationale.DecodeAll(mUnit.Rationale);
  end;
  FInfo.Documentation := '`' + FTarget.FileName + '`';
end;

function THoverLookupRun.ReadDeclaration: Boolean;
var
  mStart: TTextPosition;
begin
  if SameText(FTarget.FileName, FFileName) then
  begin
    FText := FTreeText;
  end
  else if not (Assigned(FSource.ReadText) and FSource.ReadText(FTarget.FileName, FText)) then
  begin
    TRequestDiagnostics.Reason('declarationUnreadable');
    Exit(False);
  end;
  FLines := TTextLines.SplitLines(FText);
  mStart := FTarget.Range.StartPos;
  Result := (mStart.Line >= 0) and (mStart.Line <= High(FLines));
  if not Result then
  begin
    TRequestDiagnostics.Reason('declarationOutOfRange');
    Exit;
  end;
  FInfo.Declaration := TrimRight(Copy(FLines[mStart.Line], mStart.Character + 1, MaxInt));
  FInfo.Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(FLines, mStart.Line));
  FInfo.Documentation := FInfo.Doc.ToMarkdown;
  FInfo.Deprecation := THoverValues.Deprecation(DeclarationText(FLines, FTarget.Range));
  FInfo.FileName := FTarget.FileName;
  FInfo.Line := FTarget.SelectionRange.StartPos.Line;
  FInfo.Character := FTarget.SelectionRange.StartPos.Character;
end;

function THoverLookupRun.FindOwnerUnit: Boolean;
begin
  // Aus einer Include-Datei (#500): die einbindende Unit, die Datei dahinter. Die eigene Datei
  // auch ohne Index (noch nicht gespeichert bzw. nicht im Projekt) aus dem Baum.
  Result := TIndexFiles.UnitOf(FSource.Index, FTarget.FileName, FOwner);
  if not Result and SameText(FTarget.FileName, FFileName) then
  begin
    FOwner := TIndexExtractor.Extract(FTree, FFileName);
    Result := True;
  end;
  if not Result then
  begin
    TRequestDiagnostics.Reason('unitNotIndexed');
  end
  else if not SameText(FTarget.FileName, FOwner.FileName) then
  begin
    FInfo.UnitName := FOwner.UnitName + ' (' + ExtractFileName(FTarget.FileName) + ')';
  end
  else if not SameText(FTarget.FileName, FFileName) then
  begin
    FInfo.UnitName := FOwner.UnitName;
  end;
end;

function THoverLookupRun.IsTargetSymbol(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.SelectionRange.StartPos = FTarget.SelectionRange.StartPos) and
    SameText(FOwner.SymbolFile(ASymbol), FTarget.FileName);
end;

function THoverLookupRun.ValueOf(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Constant:
      // Ganze Deklaration: Mengen und Texte über mehrere Zeilen (Resourcestrings, #38).
      Result := THoverValues.ConstantValue(DeclarationText(FLines, FTarget.Range));
    TIndexSymbolKind.TypeAlias:
      Result := SetTypeValue(FSource.Resolver, FOwner, DeclarationText(FLines, FTarget.Range));
    TIndexSymbolKind.EnumMember:
      Result := 'Ord = ' + IntToStr(EnumOrdinal(FOwner, ASymbol));
  else
    // Andere Arten haben keinen Wert für die Kopfzeile.
    Result := '';
  end;
end;

procedure THoverLookupRun.ApplySymbol(const ASymbol: TIndexSymbol);
var
  mFormFile: string;
begin
  FSelfName := ASymbol.Name;
  FDocSymbol := TResolvedSymbol.FromIndex(FOwner, ASymbol);
  FDocContainer := ASymbol.Container;
  if FDocContainer = '' then
  begin
    FDocContainer := ASymbol.Name;
  end;
  FInfo.Kind := TLspHoverTypes.KindOf(ASymbol.Kind, FInfo.Declaration);
  FInfo.Rationale := TLspRationale.OfSymbol(FOwner, ASymbol);
  FTypeSymbol := (ASymbol.Container = '') and (ASymbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
  FInfo.DocWikiUrl := TDocWiki.Url(FDelphiVersion, FOwner.UnitName, ASymbol.Container, ASymbol.Name);
  if (ASymbol.Container = '') and TWinApiDocs.IsWinApiUnit(FOwner.UnitName) then
  begin
    FInfo.WinApi := TWinApiDocs.HoverText(ASymbol.Name);
  end;
  FInfo.Value := ValueOf(ASymbol);
  if (ASymbol.Kind = TIndexSymbolKind.Field) and (ASymbol.Container <> '') then
  begin
    FInfo.FormValues := FormFieldValues(FormText(FTarget.FileName, FFileName, FTreeText, FSource.ReadText,
      mFormFile), mFormFile, ASymbol.Container, ASymbol.Name);
  end;
end;

procedure THoverLookupRun.ApplyDocumentation;
begin
  // XMLDoc mit <inheritdoc/> und den Fundorten der cref-Verweise (#654).
  if FInfo.Doc.InheritDoc then
  begin
    FInfo.Doc := TLspDocumentation.Load(FSource.Resolver, FDocSymbol, FLines, FTarget.Range.StartPos.Line,
      TLspDocumentation.Reader(FFileName, FTreeText, FSource.ReadText));
    FInfo.Documentation := FInfo.Doc.ToMarkdown;
  end;
  FInfo.DocTargets := TLspDocumentation.Targets(FSource.Resolver, FOwner, FDocContainer, FInfo.Doc);
end;

procedure THoverLookupRun.ApplyTypes;
var
  mChainName: string;
  mResolved: TResolvedSymbol;
begin
  // Typen in der Deklaration und Vererbungskette für den Atlas-Tooltip (#588).
  FInfo.Origin := TLspHoverTypes.Origin(FOwner.UnitName);
  FInfo.Links := TLspHoverTypes.Links(FSource.Resolver, FOwner, FInfo.Declaration, FSelfName);
  if not FTypeSymbol then
  begin
    Exit;
  end;
  mChainName := TLspHoverTypes.ClassRefTarget(FInfo.Declaration);
  if mChainName = '' then
  begin
    mChainName := FSelfName;
  end;
  if FSource.Resolver.ResolveTypeFrom(FOwner, mChainName, mResolved) then
  begin
    FInfo.ChainOf := mResolved.Name;
    FInfo.Ancestors := TLspHoverTypes.Chain(FSource.Resolver, mResolved);
  end;
end;

function THoverLookupRun.IsTargetClass(const ASymbol: TIndexSymbol): Boolean;
var
  mStart: TTextPosition;
begin
  mStart := FTarget.Range.StartPos;
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '') and
    ((ASymbol.Range.StartPos = mStart) or (ASymbol.SelectionRange.StartPos = mStart)) and
    SameText(FOwner.SymbolFile(ASymbol), FTarget.FileName);
end;

function THoverLookupRun.MessagesOf(const AClassName: string): string;
var
  mReader: TMessageReadText;
  mClassTree: TSyntaxTree;
begin
  mReader := MessageReader(FFileName, FTreeText, FSource.ReadText);
  if SameText(FTarget.FileName, FFileName) then
  begin
    Result := TMessageHandlers.Overview(FSource.Resolver, FTree, FFileName, AClassName, mReader).ToMarkdown;
    Exit;
  end;
  mClassTree := TSyntaxTreeCache.Parse(FText);
  try
    Result := TMessageHandlers.Overview(FSource.Resolver, mClassTree, FTarget.FileName, AClassName,
      mReader).ToMarkdown;
  finally
    mClassTree.Free;
  end;
end;

procedure THoverLookupRun.ApplyClass(const ASymbol: TIndexSymbol);
var
  mUse: TAttributeUse;
  mReader: TMemberReadText;
begin
  if TAttributes.At(FTree, FPosition, mUse) then
  begin
    FInfo.Constructors := AttributeConstructors(FOwner, ASymbol, FLines, mUse.ArgCount);
  end;
  mReader := MemberReader(FFileName, FTreeText, FSource.ReadText);
  FInfo.PublishedItems := TPublishedMembers.Collect(FSource.Index, ASymbol.Name, mReader);
  FInfo.DefaultProperty := TPublishedMembers.DefaultProperty(FSource.Index, ASymbol.Name, mReader);
  FInfo.Members := TPublishedMembers.ToMarkdown(FInfo.PublishedItems, FInfo.DefaultProperty);
  FInfo.Messages := MessagesOf(ASymbol.Name);
end;

function THoverLookupRun.Run(const ADelphiVersion: string): THoverInfo;
var
  mSymbol: TIndexSymbol;
begin
  FDelphiVersion := ADelphiVersion;
  FInfo := Default(THoverInfo);
  if not TryNumber and FindTarget and not TryUnitName and ReadDeclaration and FindOwnerUnit then
  begin
    for mSymbol in FOwner.Symbols do
    begin
      if IsTargetSymbol(mSymbol) then
      begin
        ApplySymbol(mSymbol);
        Break;
      end;
    end;
    ApplyDocumentation;
    ApplyTypes;
    for mSymbol in FOwner.Symbols do
    begin
      if IsTargetClass(mSymbol) then
      begin
        ApplyClass(mSymbol);
        Break;
      end;
    end;
  end;
  Result := FInfo;
end;

{ TLspHoverLookup }

class function TLspHoverLookup.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo;
var
  mRun: THoverLookupRun;
begin
  mRun := THoverLookupRun.Create(ASource, ATree, ATreeText, AFileName, APosition);
  try
    Result := mRun.Run(ADelphiVersion);
  finally
    mRun.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Hover.Lookup', cTexts);

end.
