unit Atlas.UI.Results.Texts;

// Texte der Zeilen im Ergebnisfenster (#400): Fundstellen und erschlossene Treffer (#1119), Hierarchien,
// Auswirkungsanalyse (#1120) und Datenfluss (#690). Reine Funktionen, ohne Steuerelemente.

interface

uses
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Results.DataFlow;

type
  TAtlasResultsTexts = record
    /// <summary>Text einer Fundstelle: "12: Kunde.Laden;" bzw. mit Vorschau "alt  →  neu"; erschlossen
    /// "≈ 12: S.Speichern;  [über Interface]" (#1119).</summary>
    class function EntryText(const AEntry: TAtlasResultEntry): string; static;
    /// <summary>Kurzer Grund eines erschlossenen Treffers, etwa "über Interface"; '' bei sicheren.</summary>
    class function ReasonText(const AConfidence: TAtlasConfidence): string; static;
    /// <summary>Text eines Hierarchie-Eintrags: "Laden · TKunde  (Kunden.pas:12)".</summary>
    class function HierarchyText(const AItem: TAtlasHierarchyItem): string; static;
    /// <summary>Text einer betroffenen Stelle (#1120): wie HierarchyText, mit Art (Override, Umsetzung …), Zahl
    /// der Verwendungen und Test-Kennzeichen.</summary>
    class function ImpactPlaceText(const APlace: TAtlasImpactPlace): string; static;
    /// <summary>"Formular: OnClick = Button1Click  (Main.dfm:12)".</summary>
    class function ImpactFormText(const AForm: TAtlasImpactForm): string; static;
    /// <summary>Je erreichte Grenze eine Zeile; leer ohne.</summary>
    class function ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>; static;
    /// <summary>"Zuweisung" bzw. bei mehreren "3 Zuweisungen".</summary>
    class function FlowKindText(AKind: TAtlasDataFlowKind; ACount: Integer): string; static;
    /// <summary>"Zuweisung: A + B · über Summe  ⚠ unsicher: Zeiger   Haupt.pas:12: X := A + B;"; bei
    /// zusammengefassten Stellen ohne Fundort (der steht darunter).</summary>
    class function FlowNodeText(const ANode: TAtlasDataFlowNode): string; static;
    /// <summary>"Haupt.pas:12: X := A + B;".</summary>
    class function FlowPlaceText(const APlace: TAtlasDataFlowPlace): string; static;
    /// <summary>"← Summe  (Daten.pas:11)" bzw. "→ A …", mit "· Konstante", "· Zyklus", "· Tiefe erreicht".</summary>
    class function FlowSourceText(const AChild: TAtlasDataFlowChild; ADirection: TAtlasDataFlowDirection): string;
      static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

{ TAtlasResultsTexts }

class function TAtlasResultsTexts.ReasonText(const AConfidence: TAtlasConfidence): string;
begin
  Result := '';
  if not AConfidence.Inferred then
  begin
    Exit;
  end;
  if AConfidence.Reason = 'interface' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInterface);
  end
  else if AConfidence.Reason = 'virtual' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonVirtual);
  end
  else if AConfidence.Reason = 'ambiguous' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonAmbiguous);
  end
  else if AConfidence.Reason = 'unresolved' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonUnresolved);
  end
  else if AConfidence.Reason = 'inactiveBranch' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInactiveBranch);
  end
  else if AConfidence.Reason = 'text' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ReferenceReasonText);
  end
  else
  begin
    // Gründe neuerer Server: wie geliefert.
    Result := AConfidence.Reason;
  end;
end;

class function TAtlasResultsTexts.EntryText(const AEntry: TAtlasResultEntry): string;
begin
  Result := Format('%d: %s', [AEntry.Line + 1, AEntry.Text]);
  if AEntry.Detail <> '' then
  begin
    Result := Result + '  →  ' + AEntry.Detail;
  end;
  if AEntry.Confidence.Inferred then
  begin
    Result := '≈ ' + Result + '  [' + ReasonText(AEntry.Confidence) + ']';
  end;
end;

class function TAtlasResultsTexts.HierarchyText(const AItem: TAtlasHierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Detail <> '' then
  begin
    Result := Result + ' · ' + AItem.Detail;
  end;
  if AItem.FileName <> '' then
  begin
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AItem.FileName), AItem.Line + 1]);
  end;
  if AItem.Confidence.Inferred then
  begin
    Result := '≈ ' + Result + '  [' + ReasonText(AItem.Confidence) + ']';
  end;
end;

class function TAtlasResultsTexts.ImpactPlaceText(const APlace: TAtlasImpactPlace): string;
var
  Edge: string;
begin
  if APlace.Terminal then
  begin
    Result := APlace.Item.Name + ' · ' + TAtlasStrings.Text(TAtlasTextId.ImpactUnitLevel) +
      Format('  (%s:%d)', [ExtractFileName(APlace.Item.FileName), APlace.UseLine + 1]);
  end
  else
  begin
    Result := HierarchyText(APlace.Item);
  end;
  Edge := '';
  if APlace.Edge = 'reference' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeReference);
  end
  else if APlace.Edge = 'override' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeOverride);
  end
  else if APlace.Edge = 'baseMethod' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeBase);
  end
  else if APlace.Edge = 'interfaceMethod' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeInterface);
  end
  else if APlace.Edge = 'implementation' then
  begin
    Edge := TAtlasStrings.Text(TAtlasTextId.ImpactEdgeImplementation);
  end;
  if Edge <> '' then
  begin
    Result := Result + '  · ' + Edge;
  end;
  if APlace.UseCount > 1 then
  begin
    Result := Result + Format('  ×%d', [APlace.UseCount]);
  end;
  if APlace.Test <> '' then
  begin
    Result := Result + '  · Test';
  end;
end;

class function TAtlasResultsTexts.ImpactFormText(const AForm: TAtlasImpactForm): string;
begin
  Result := Format(TAtlasStrings.Text(TAtlasTextId.ImpactForm), [AForm.Text, ExtractFileName(AForm.FileName),
    AForm.Line + 1]);
end;

class function TAtlasResultsTexts.ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>;
begin
  Result := nil;
  if AImpact.DepthReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitDepth), [AImpact.Depth,
      AImpact.Unexpanded])];
  end;
  if AImpact.CountReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitCount), [AImpact.MaxPlaces])];
  end;
  if AImpact.TimeReached then
  begin
    Result := Result + [Format(TAtlasStrings.Text(TAtlasTextId.ImpactLimitTime), [AImpact.TimeoutMs])];
  end;
end;

class function TAtlasResultsTexts.FlowKindText(AKind: TAtlasDataFlowKind; ACount: Integer): string;
const
  Singular: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignment,
    TAtlasTextId.DataFlowVarArgument, TAtlasTextId.DataFlowOutArgument, TAtlasTextId.DataFlowInput,
    TAtlasTextId.DataFlowInitializer, TAtlasTextId.DataFlowLoop, TAtlasTextId.DataFlowCallerArgument,
    TAtlasTextId.DataFlowReturn, TAtlasTextId.DataFlowPropertyWrite, TAtlasTextId.DataFlowPropertyRead,
    TAtlasTextId.DataFlowModify, TAtlasTextId.DataFlowArgument, TAtlasTextId.DataFlowOutput, TAtlasTextId.DataFlowUse,
    TAtlasTextId.DataFlowConstant, TAtlasTextId.DataFlowOutside, TAtlasTextId.DataFlowAddress,
    TAtlasTextId.DataFlowPlace);
  Plural: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignments,
    TAtlasTextId.DataFlowVarArguments, TAtlasTextId.DataFlowOutArguments, TAtlasTextId.DataFlowInputs,
    TAtlasTextId.DataFlowInitializers, TAtlasTextId.DataFlowLoops, TAtlasTextId.DataFlowCallerArguments,
    TAtlasTextId.DataFlowReturns, TAtlasTextId.DataFlowPropertyWrites, TAtlasTextId.DataFlowPropertyReads,
    TAtlasTextId.DataFlowModifies, TAtlasTextId.DataFlowArguments, TAtlasTextId.DataFlowOutputs,
    TAtlasTextId.DataFlowUses, TAtlasTextId.DataFlowConstants, TAtlasTextId.DataFlowOutsides,
    TAtlasTextId.DataFlowAddresses, TAtlasTextId.DataFlowPlaces);
begin
  if ACount > 1 then
  begin
    Result := Format('%d %s', [ACount, TAtlasStrings.Text(Plural[AKind])]);
  end
  else
  begin
    Result := TAtlasStrings.Text(Singular[AKind]);
  end;
end;

function UnsafeText(const AReason: string): string;
begin
  if AReason = 'pointer' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.DataFlowUnsafePointer);
  end
  else if AReason = 'address' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.DataFlowUnsafeAddress);
  end
  else if AReason = 'move' then
  begin
    Result := 'Move';
  end
  else if AReason = 'fillchar' then
  begin
    Result := 'FillChar';
  end
  else
  begin
    Result := AReason;
  end;
end;

class function TAtlasResultsTexts.FlowPlaceText(const APlace: TAtlasDataFlowPlace): string;
begin
  Result := Format('%s:%d: %s', [ExtractFileName(APlace.FileName), APlace.Line + 1, APlace.LineText]);
end;

class function TAtlasResultsTexts.FlowNodeText(const ANode: TAtlasDataFlowNode): string;
var
  Origin: TAtlasDataFlowOrigin;
begin
  Result := FlowKindText(ANode.Kind, Length(ANode.Places));
  if ANode.Detail <> '' then
  begin
    Result := Result + ': ' + ANode.Detail;
  end;
  if ANode.Via <> '' then
  begin
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.DataFlowVia, [ANode.Via]);
  end;
  // Herkunft eines Blatts nur, wo die Art sie nicht schon nennt.
  Origin := TAtlasDataFlowTree.Origin(ANode);
  case Origin of
    TAtlasDataFlowOrigin.Literal:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginLiteral);
    TAtlasDataFlowOrigin.Open:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginOpen);
    TAtlasDataFlowOrigin.Outside:
      if ANode.Kind <> TAtlasDataFlowKind.Outside then
      begin
        Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginOutside);
      end;
    TAtlasDataFlowOrigin.Address:
      Result := Result + ' — ' + TAtlasStrings.Text(TAtlasTextId.DataFlowOriginAddress);
    TAtlasDataFlowOrigin.None, TAtlasDataFlowOrigin.Input, TAtlasDataFlowOrigin.Output, TAtlasDataFlowOrigin.Use,
    TAtlasDataFlowOrigin.Constant: ;
  end;
  if ANode.Unsafe then
  begin
    Result := Result + '  ⚠ ' + TAtlasStrings.Fmt(TAtlasTextId.DataFlowUnsafe, [UnsafeText(ANode.UnsafeReason)]);
  end;
  if Length(ANode.Places) = 1 then
  begin
    Result := Result + '   ' + FlowPlaceText(ANode.Places[0]);
  end;
end;

class function TAtlasResultsTexts.FlowSourceText(const AChild: TAtlasDataFlowChild;
  ADirection: TAtlasDataFlowDirection): string;
begin
  if ADirection = TAtlasDataFlowDirection.Targets then
  begin
    Result := '→ ';
  end
  else
  begin
    Result := '← ';
  end;
  Result := Result + AChild.Source.Name;
  if AChild.Source.FileName <> '' then
  begin
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AChild.Source.FileName), AChild.Source.Line + 1]);
  end;
  case AChild.Source.Leaf of
    TAtlasDataFlowLeaf.Constant:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafConstant);
    TAtlasDataFlowLeaf.Outside:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafOutside);
    TAtlasDataFlowLeaf.Cycle:
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafCycle);
  else
    if AChild.DepthReached then
    begin
      Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.DataFlowLeafDepth);
    end;
  end;
end;

end.
