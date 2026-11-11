unit Atlas.Common.Lsp.Documentation;

// XMLDoc für Hover, Parameter-Hint und Vervollständigung (#654).
//
// Load liest den ///-Kommentar über einer Deklaration (TXmlDoc) und löst
// <inheritdoc/> auf: ohne cref über den überschriebenen Member im nächsten
// Vorfahren bzw. in implementierten Interfaces, bei Typen über den Vorfahrtyp;
// mit cref über das genannte Symbol. Eigene Abschnitte gehen vor, fehlende
// kommen vom Vorfahren (TXmlDoc.Inherit), auch über mehrere Stufen.
//
// ToJson gibt die Abschnitte strukturiert aus: je Abschnitt Art, Name und
// Teilstücke. Verweise (cref) tragen den Fundort des Ziels (name, unit, file,
// line, character), damit das Plugin sie wie die Typnamen der Deklaration
// anklickbar macht (#588). HintsJson gibt die Anzeige-Einstellungen "hints"
// des Projekts an das Plugin weiter (atlas.json vor den Plugin-Einstellungen).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.XmlDoc;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  TDocReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Einstellungen "hints" für das Dokument AUri (#654).</summary>
  TDocHintsProvider = reference to function(const AUri: string): THintSettings;

  /// <summary>Fundort eines cref (0-basiert, Position des Namens).</summary>
  TDocTarget = record
    Cref: string;
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TLspDocumentation = class
  public const
    /// <summary>Höchstens so viele Stufen inheritdoc hintereinander.</summary>
    cMaxInheritDepth = 8;
  private type
    TLoader = class
    private
      FResolver: TNameResolver;
      FReadText: TDocReadText;
      FLines: TDictionary<string, TArray<string>>;
      function LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
      function DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function OwnerOf(const ASymbol: TResolvedSymbol; out AOwner: TResolvedSymbol): Boolean;
      function BasesOf(const AOwner: TResolvedSymbol): TArray<TResolvedSymbol>;
      function AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc; ADepth: Integer): TXmlDoc;
    public
      constructor Create(AResolver: TNameResolver; const AReadText: TDocReadText);
      destructor Destroy; override;
    end;
  public
    /// <summary>Kommentar über ALine (0-basiert) in ALines. Ist ASymbol gesetzt (Found) und steht
    /// &lt;inheritdoc/&gt; im Kommentar, kommt die Doku des Vorfahren bzw. des cref-Ziels dazu; AReadText
    /// liest deren Dateien.</summary>
    class function Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol; const ALines: TArray<string>;
      ALine: Integer; const AReadText: TDocReadText): TXmlDoc; static;
    /// <summary>Fundorte aller cref in ADoc (Verweise und Exceptions), von AFromUnit bzw. AContainer aus
    /// aufgelöst; nicht auflösbare fehlen.</summary>
    class function Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const AContainer: string;
      const ADoc: TXmlDoc): TArray<TDocTarget>; static;
    /// <summary>Abschnitte und Teilstücke als JSON; Verweise mit Eintrag in ATargets tragen ihren Fundort.</summary>
    class function ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject; static;
    /// <summary>Anzeige-Einstellungen für das Plugin: {"full": …, "maxLines": …} (#654).</summary>
    class function HintsJson(const AHints: THintSettings): TJSONObject; static;
    /// <summary>Liest AOwnFile aus AOwnText (Editorinhalt, auch ungespeichert), andere Dateien über
    /// AReadText.</summary>
    class function Reader(const AOwnFile, AOwnText: string; const AReadText: TDocReadText): TDocReadText; static;
    /// <summary>Text in Zeilen (CRLF, LF oder CR); wie TTextLines.SplitLines.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
  end;

implementation

uses
  Atlas.Text.Lines,
  Atlas.Common.Lsp.IdeUnits;

{ TLspDocumentation.TLoader }

constructor TLspDocumentation.TLoader.Create(AResolver: TNameResolver; const AReadText: TDocReadText);
begin
  inherited Create;
  FResolver := AResolver;
  FReadText := AReadText;
  FLines := TDictionary<string, TArray<string>>.Create;
end;

destructor TLspDocumentation.TLoader.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TLspDocumentation.TLoader.LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mText: string;
begin
  if FLines.TryGetValue(UpperCase(AFileName), ALines) then
  begin
    Exit(True);
  end;
  Result := Assigned(FReadText) and FReadText(AFileName, mText);
  if not Result then
  begin
    Exit;
  end;
  ALines := TLspDocumentation.SplitLines(mText);
  FLines.AddOrSetValue(UpperCase(AFileName), ALines);
end;

function TLspDocumentation.TLoader.DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  mLines: TArray<string>;
begin
  Result := Default(TXmlDoc);
  if (ASymbol.FileName = '') or not LinesOf(ASymbol.FileName, mLines) then
  begin
    Exit;
  end;
  Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(mLines, ASymbol.Range.StartPos.Line));
  if Result.InheritDoc then
  begin
    Result := Resolve(ASymbol, Result, ADepth);
  end;
end;

function TLspDocumentation.TLoader.OwnerOf(const ASymbol: TResolvedSymbol; out AOwner: TResolvedSymbol): Boolean;
var
  mOwnerUnit: TUnitIndex;
begin
  // Ein Typ ist sein eigener Träger, ein Member gehört zum Typ ASymbol.Container.
  if ASymbol.Container = '' then
  begin
    AOwner := ASymbol;
    Result := ASymbol.IsType;
  end
  else
  begin
    Result := FResolver.DeclaringUnit(ASymbol, mOwnerUnit) and
      FResolver.ResolveTypeFrom(mOwnerUnit, ASymbol.Container, AOwner);
  end;
end;

function TLspDocumentation.TLoader.BasesOf(const AOwner: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mTypeUnit: TUnitIndex;
  mBase: TResolvedSymbol;
  mIndex: Integer;
begin
  // Vorfahr zuerst, dann die implementierten Interfaces.
  Result := nil;
  // Helfer: nur der Vorfahr-Helfer (#848); der Zieltyp am Ende von Ancestors ist kein Vorfahr.
  if AOwner.SymbolKind = TIndexSymbolKind.HelperType then
  begin
    if FResolver.Queries.HelperParent(AOwner, mBase) then
    begin
      Result := [mBase];
    end;
    Exit;
  end;
  if FResolver.AncestorOf(AOwner, mBase) then
  begin
    Result := Result + [mBase];
  end;
  if not FResolver.DeclaringUnit(AOwner, mTypeUnit) then
  begin
    Exit;
  end;
  for mIndex := 1 to High(AOwner.Ancestors) do
  begin
    if FResolver.ResolveTypeFrom(mTypeUnit, AOwner.Ancestors[mIndex], mBase) then
    begin
      Result := Result + [mBase];
    end;
  end;
end;

function TLspDocumentation.TLoader.AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  mOwner, mBase, mCandidate: TResolvedSymbol;
begin
  Result := Default(TXmlDoc);
  if (ADepth > TLspDocumentation.cMaxInheritDepth) or not OwnerOf(ASymbol, mOwner) then
  begin
    Exit;
  end;
  for mBase in BasesOf(mOwner) do
  begin
    mCandidate := mBase;
    if (ASymbol.Container <> '') and not FResolver.DeclaredMember(mBase, ASymbol.Name, mCandidate) then
    begin
      Continue;
    end;
    Result := DocOf(mCandidate, ADepth + 1);
    // Ohne eigene Doku dort weiter oben suchen.
    if Result.IsEmpty then
    begin
      Result := AncestorDoc(mCandidate, ADepth + 1);
    end;
    if not Result.IsEmpty then
    begin
      Exit;
    end;
  end;
end;

function TLspDocumentation.TLoader.Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc;
  ADepth: Integer): TXmlDoc;
var
  mFromUnit: TUnitIndex;
  mTarget: TResolvedSymbol;
  mBase: TXmlDoc;
begin
  mBase := Default(TXmlDoc);
  if ADepth <= TLspDocumentation.cMaxInheritDepth then
  begin
    if ADoc.InheritCref <> '' then
    begin
      if FResolver.DeclaringUnit(ASymbol, mFromUnit) and
        FResolver.LocateCref(mFromUnit, ASymbol.Container, ADoc.InheritCref, mTarget) then
      begin
        mBase := DocOf(mTarget, ADepth + 1);
      end;
    end
    else
    begin
      mBase := AncestorDoc(ASymbol, ADepth);
    end;
  end;
  Result := ADoc.Inherit(mBase);
end;

{ TLspDocumentation }

class function TLspDocumentation.SplitLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
end;

class function TLspDocumentation.HintsJson(const AHints: THintSettings): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('expand', AHints.XmlDocExpand);
  Result.AddPair('maxLines', TJSONNumber.Create(AHints.XmlDocMaxLines));
end;

class function TLspDocumentation.Reader(const AOwnFile, AOwnText: string;
  const AReadText: TDocReadText): TDocReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      if SameText(AName, AOwnFile) then
      begin
        AText := AOwnText;
        Exit(True);
      end;
      Result := Assigned(AReadText) and AReadText(AName, AText);
    end;
end;

class function TLspDocumentation.Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol;
  const ALines: TArray<string>; ALine: Integer; const AReadText: TDocReadText): TXmlDoc;
var
  mLoader: TLoader;
begin
  Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(ALines, ALine));
  if not Result.InheritDoc or (AResolver = nil) or not ASymbol.Found then
  begin
    Exit;
  end;
  mLoader := TLoader.Create(AResolver, AReadText);
  try
    Result := mLoader.Resolve(ASymbol, Result, 0);
  finally
    mLoader.Free;
  end;
end;

class function TLspDocumentation.Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex;
  const AContainer: string; const ADoc: TXmlDoc): TArray<TDocTarget>;
var
  mSeen: TDictionary<string, Boolean>;
  mSection: TXmlDocSection;
  mRun: TXmlDocRun;

  procedure Add(const ACref: string);
  var
    mSymbol: TResolvedSymbol;
    mTarget: TDocTarget;
  begin
    if (ACref = '') or mSeen.ContainsKey(ACref) then
    begin
      Exit;
    end;
    mSeen.Add(ACref, True);
    if not AResolver.LocateCref(AFromUnit, AContainer, ACref, mSymbol) then
    begin
      Exit;
    end;
    mTarget.Cref := ACref;
    mTarget.Name := mSymbol.Name;
    mTarget.UnitName := mSymbol.UnitName;
    mTarget.FileName := mSymbol.FileName;
    mTarget.Line := mSymbol.SelectionRange.StartPos.Line;
    mTarget.Character := mSymbol.SelectionRange.StartPos.Character;
    Result := Result + [mTarget];
  end;

begin
  Result := nil;
  if AResolver = nil then
  begin
    Exit;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSection in ADoc.Sections do
    begin
      if mSection.Kind = TXmlDocSectionKind.Exception then
      begin
        Add(mSection.Name);
      end;
      for mRun in mSection.Runs do
      begin
        if mRun.Kind = TXmlDocRunKind.Ref then
        begin
          Add(mRun.Target);
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function FindTarget(const ATargets: TArray<TDocTarget>; const ACref: string; out ATarget: TDocTarget): Boolean;
var
  mTarget: TDocTarget;
begin
  for mTarget in ATargets do
  begin
    if mTarget.Cref = ACref then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name, Unit und Fundort; Ersatz-Units der IDE (atlas-ide:…) gibt es nicht als Datei: ohne Fundort,
/// also ohne Sprungziel.</summary>
procedure AddLocation(AObject: TJSONObject; const ATarget: TDocTarget);
begin
  AObject.AddPair('name', ATarget.Name);
  if ATarget.UnitName <> '' then
  begin
    AObject.AddPair('unit', ATarget.UnitName);
  end;
  if TIdeUnits.IsIdePath(ATarget.FileName) then
  begin
    Exit;
  end;
  AObject.AddPair('file', ATarget.FileName);
  AObject.AddPair('line', TJSONNumber.Create(ATarget.Line));
  AObject.AddPair('character', TJSONNumber.Create(ATarget.Character));
end;

/// <summary>Ein Teilstück als JSON; ein Verweis mit Eintrag in ATargets trägt seinen Fundort.</summary>
function RunJson(const ARun: TXmlDocRun; const ATargets: TArray<TDocTarget>): TJSONObject;
var
  mTarget: TDocTarget;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', TXmlDoc.RunKindName(ARun.Kind));
  if ARun.Text <> '' then
  begin
    Result.AddPair('text', ARun.Text);
  end;
  if ARun.Target <> '' then
  begin
    Result.AddPair('target', ARun.Target);
  end;
  if TXmlDocStyle.Bold in ARun.Styles then
  begin
    Result.AddPair('bold', TJSONTrue.Create);
  end;
  if TXmlDocStyle.Italic in ARun.Styles then
  begin
    Result.AddPair('italic', TJSONTrue.Create);
  end;
  if ARun.Level > 0 then
  begin
    Result.AddPair('level', TJSONNumber.Create(ARun.Level));
  end;
  if (ARun.Kind = TXmlDocRunKind.Ref) and FindTarget(ATargets, ARun.Target, mTarget) then
  begin
    AddLocation(Result, mTarget);
  end;
end;

class function TLspDocumentation.ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject;
var
  mSections, mRuns: TJSONArray;
  mSection: TXmlDocSection;
  mRun: TXmlDocRun;
  mItem, mRefItem: TJSONObject;
  mTarget: TDocTarget;
begin
  Result := TJSONObject.Create;
  mSections := TJSONArray.Create;
  Result.AddPair('sections', mSections);
  for mSection in ADoc.Sections do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('kind', TXmlDoc.SectionName(mSection.Kind));
    if mSection.Name <> '' then
    begin
      mItem.AddPair('name', mSection.Name);
    end;
    if (mSection.Kind = TXmlDocSectionKind.Exception) and FindTarget(ATargets, mSection.Name, mTarget) then
    begin
      mRefItem := TJSONObject.Create;
      AddLocation(mRefItem, mTarget);
      mItem.AddPair('ref', mRefItem);
    end;
    mRuns := TJSONArray.Create;
    for mRun in mSection.Runs do
    begin
      mRuns.AddElement(RunJson(mRun, ATargets));
    end;
    mItem.AddPair('runs', mRuns);
    mSections.AddElement(mItem);
  end;
end;

end.
