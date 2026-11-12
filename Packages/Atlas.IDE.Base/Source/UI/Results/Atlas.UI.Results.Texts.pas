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
  Atlas.UI.Strings,
  Atlas.UI.Results.Strings;

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
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonInterface);
  end
  else if AConfidence.Reason = 'virtual' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonVirtual);
  end
  else if AConfidence.Reason = 'ambiguous' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonAmbiguous);
  end
  else if AConfidence.Reason = 'unresolved' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonUnresolved);
  end
  else if AConfidence.Reason = 'inactiveBranch' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonInactiveBranch);
  end
  else if AConfidence.Reason = 'text' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonText);
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
  mEdge: string;
begin
  if APlace.Terminal then
  begin
    Result := APlace.Item.Name + ' · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactUnitLevel) +
      Format('  (%s:%d)', [ExtractFileName(APlace.Item.FileName), APlace.UseLine + 1]);
  end
  else
  begin
    Result := HierarchyText(APlace.Item);
  end;
  mEdge := '';
  if APlace.Edge = 'reference' then
  begin
    mEdge := TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeReference);
  end
  else if APlace.Edge = 'override' then
  begin
    mEdge := TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeOverride);
  end
  else if APlace.Edge = 'baseMethod' then
  begin
    mEdge := TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeBase);
  end
  else if APlace.Edge = 'interfaceMethod' then
  begin
    mEdge := TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeInterface);
  end
  else if APlace.Edge = 'implementation' then
  begin
    mEdge := TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeImplementation);
  end;
  if mEdge <> '' then
  begin
    Result := Result + '  · ' + mEdge;
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
  Result := Format(TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactForm), [AForm.Text,
    ExtractFileName(AForm.FileName),
    AForm.Line + 1]);
end;

class function TAtlasResultsTexts.ImpactLimitTexts(const AImpact: TAtlasImpact): TArray<string>;
begin
  Result := nil;
  if AImpact.DepthReached then
  begin
    Result := Result + [Format(TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactLimitDepth), [AImpact.Depth,
      AImpact.Unexpanded])];
  end;
  if AImpact.CountReached then
  begin
    Result := Result + [Format(TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactLimitCount), [AImpact.MaxPlaces])];
  end;
  if AImpact.TimeReached then
  begin
    Result := Result + [Format(TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactLimitTime), [AImpact.TimeoutMs])];
  end;
end;

class function TAtlasResultsTexts.FlowKindText(AKind: TAtlasDataFlowKind; ACount: Integer): string;
const
  cSingular: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignment,
    TAtlasTextId.DataFlowVarArgument, TAtlasTextId.DataFlowOutArgument, TAtlasTextId.DataFlowInput,
    TAtlasTextId.DataFlowInitializer, TAtlasTextId.DataFlowLoop, TAtlasTextId.DataFlowCallerArgument,
    TAtlasTextId.DataFlowReturn, TAtlasTextId.DataFlowPropertyWrite, TAtlasTextId.DataFlowPropertyRead,
    TAtlasTextId.DataFlowModify, TAtlasTextId.DataFlowArgument, TAtlasTextId.DataFlowOutput, TAtlasTextId.DataFlowUse,
    TAtlasTextId.DataFlowConstant, TAtlasTextId.DataFlowOutside, TAtlasTextId.DataFlowAddress,
    TAtlasTextId.DataFlowPlace);
  cPlural: array[TAtlasDataFlowKind] of TAtlasTextId = (TAtlasTextId.DataFlowAssignments,
    TAtlasTextId.DataFlowVarArguments, TAtlasTextId.DataFlowOutArguments, TAtlasTextId.DataFlowInputs,
    TAtlasTextId.DataFlowInitializers, TAtlasTextId.DataFlowLoops, TAtlasTextId.DataFlowCallerArguments,
    TAtlasTextId.DataFlowReturns, TAtlasTextId.DataFlowPropertyWrites, TAtlasTextId.DataFlowPropertyReads,
    TAtlasTextId.DataFlowModifies, TAtlasTextId.DataFlowArguments, TAtlasTextId.DataFlowOutputs,
    TAtlasTextId.DataFlowUses, TAtlasTextId.DataFlowConstants, TAtlasTextId.DataFlowOutsides,
    TAtlasTextId.DataFlowAddresses, TAtlasTextId.DataFlowPlaces);
begin
  if ACount > 1 then
  begin
    Result := Format('%d %s', [ACount, TAtlasStrings.Text(cPlural[AKind])]);
  end
  else
  begin
    Result := TAtlasStrings.Text(cSingular[AKind]);
  end;
end;

function UnsafeText(const AReason: string): string;
begin
  if AReason = 'pointer' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowUnsafePointer);
  end
  else if AReason = 'address' then
  begin
    Result := TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowUnsafeAddress);
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
  mOrigin: TAtlasDataFlowOrigin;
begin
  Result := FlowKindText(ANode.Kind, Length(ANode.Places));
  if ANode.Detail <> '' then
  begin
    Result := Result + ': ' + ANode.Detail;
  end;
  if ANode.Via <> '' then
  begin
    Result := Result + ' · ' + TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowVia, [ANode.Via]);
  end;
  // Herkunft eines Blatts nur, wo die Art sie nicht schon nennt.
  mOrigin := TAtlasDataFlowTree.Origin(ANode);
  case mOrigin of
    TAtlasDataFlowOrigin.Literal:
      Result := Result + ' — ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginLiteral);
    TAtlasDataFlowOrigin.Open:
      Result := Result + ' — ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginOpen);
    TAtlasDataFlowOrigin.Outside:
      if ANode.Kind <> TAtlasDataFlowKind.Outside then
      begin
        Result := Result + ' — ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginOutside);
      end;
    TAtlasDataFlowOrigin.Address:
      Result := Result + ' — ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOriginAddress);
    TAtlasDataFlowOrigin.None, TAtlasDataFlowOrigin.Input, TAtlasDataFlowOrigin.Output, TAtlasDataFlowOrigin.Use,
    TAtlasDataFlowOrigin.Constant: ;
  end;
  if ANode.Unsafe then
  begin
    Result := Result + '  ⚠ ' + TAtlasResultsStrings.Fmt(TAtlasResultsTextId.DataFlowUnsafe,
      [UnsafeText(ANode.UnsafeReason)]);
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
      Result := Result + ' · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafConstant);
    TAtlasDataFlowLeaf.Outside:
      Result := Result + ' · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafOutside);
    TAtlasDataFlowLeaf.Cycle:
      Result := Result + ' · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafCycle);
  else
    if AChild.DepthReached then
    begin
      Result := Result + ' · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowLeafDepth);
    end;
  end;
end;

end.
