unit Atlas.Common.Editing.GenericLists.Elements;

// Elemente der Listenumwandlung prüfen (#1105, #1106): Jedes Argument, das in die Liste kommt (Add, Insert,
// L[I] := X …), muss vom Elementtyp T oder einem Nachfahren sein. Zeiger und Ganzzahlen verhindern die Umwandlung,
// ein unbekannter Typ macht sie unsicher (nicht in source.fixAll).

interface

uses
  System.Generics.Collections,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.GenericLists.Source,
  Atlas.Common.Editing.GenericLists.State;

type
  {$SCOPEDENUMS ON}
  /// <summary>Passt ein Element zum Elementtyp?</summary>
  TGenericListElementFit = (Fits, Unknown, Wrong);
  {$SCOPEDENUMS OFF}

  /// <summary>Prüft die Elemente einer Liste gegen ihren Elementtyp.</summary>
  TGenericListElementCheck = record
  private
    FResolver: TNameResolver;
    FFiles: TObjectList<TGenericListSource>;
    FListName: string;
    FItemType: string;
    FProblem: string;
    function CheckDescendant(const AElement: TGenericListElement): TGenericListElementFit;
  public
    /// <summary>AListName ist der Name der Liste für die Meldung, AItemType der Elementtyp wie im ersten
    /// Cast.</summary>
    constructor Create(AResolver: TNameResolver; AFiles: TObjectList<TGenericListSource>; const AListName,
      AItemType: string);
    /// <summary>Ordnet AElement ein; bei Wrong nennt Problem den Grund.</summary>
    function Check(const AElement: TGenericListElement): TGenericListElementFit;
    property Problem: string read FProblem;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TElementsText = (TakesValuesOfType, TakesValuesOfType2);

const
  cTexts: array[TElementsText] of TAtlasText = (
    (De: '%s nimmt in Zeile %d Werte vom Typ %s auf, nicht %s';
     En: '%0:s takes values of type %2:s in line %1:d, not %3:s'),
    (De: '%s nimmt in Zeile %d Werte vom Typ %s auf'; En: '%0:s takes values of type %2:s in line %1:d'));

{$SCOPEDENUMS OFF}

constructor TGenericListElementCheck.Create(AResolver: TNameResolver; AFiles: TObjectList<TGenericListSource>;
  const AListName, AItemType: string);
begin
  FResolver := AResolver;
  FFiles := AFiles;
  FListName := AListName;
  FItemType := AItemType;
  FProblem := '';
end;

function TGenericListElementCheck.CheckDescendant(const AElement: TGenericListElement): TGenericListElementFit;
var
  mSource: TGenericListSource;
  mActual, mTarget: TResolvedSymbol;
  mOffset: Integer;
begin
  // Nachfahre von T? Beide Namen so aufgelöst, wie sie an der Stelle stehen.
  mSource := FFiles[AElement.FileIndex];
  mOffset := AElement.Node.StartOffset;
  mActual := FResolver.ResolveChain(mSource.Tree, mSource.FileName, AElement.TypeName.Split(['.']), mOffset);
  mTarget := FResolver.ResolveChain(mSource.Tree, mSource.FileName, FItemType.Split(['.']), mOffset);
  if not (mActual.Found and mActual.IsType and mTarget.Found and mTarget.IsType) then
  begin
    Exit(TGenericListElementFit.Unknown);
  end;
  Result := TGenericListElementFit.Fits;
  if not FResolver.Queries.TypeDescendsFrom(mSource.Tree, mSource.FileName, mOffset, AElement.TypeName,
    FItemType) then
  begin
    FProblem := cTexts[TElementsText.TakesValuesOfType].Fmt([FListName,
      AElement.Node.StartPos.Line + 1, AElement.TypeName, FItemType]);
    Result := TGenericListElementFit.Wrong;
  end;
end;

function TGenericListElementCheck.Check(const AElement: TGenericListElement): TGenericListElementFit;
var
  mTypeName: string;
begin
  mTypeName := TGenericListSyntax.LastName(AElement.TypeName);
  if (AElement.TypeName = 'nil') or SameText(mTypeName, TGenericListSyntax.LastName(FItemType)) then
  begin
    Result := TGenericListElementFit.Fits;
  end
  else if AElement.TypeName = '' then
  begin
    Result := TGenericListElementFit.Unknown;
  end
  else if TGenericListNames.IsScalarType(mTypeName) then
  begin
    FProblem := cTexts[TElementsText.TakesValuesOfType2].Fmt([FListName, AElement.Node.StartPos.Line + 1,
      mTypeName]);
    Result := TGenericListElementFit.Wrong;
  end
  else
  begin
    Result := CheckDescendant(AElement);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.GenericLists.Elements', cTexts);

end.
