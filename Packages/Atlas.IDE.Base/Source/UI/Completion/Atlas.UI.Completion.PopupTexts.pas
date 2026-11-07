unit Atlas.UI.Completion.PopupTexts;

// Texte des Vervollständigungs-Popups (#410) in der Sprache der IDE: Marken, Detail, Art für die Sprachausgabe,
// Überschriften der Gruppen, Fußzeile und Warnleiste. Reine Funktionen über Einträge und Anzeigereihenfolge,
// ohne Fenster; das Popup (Atlas.UI.Completion.Popup) zeichnet sie nur.

interface

uses
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Presentation;

type
  /// <summary>Was die Fußzeile über die gezeigte Liste wissen muss.</summary>
  TAtlasCompletionList = record
    Items: TAtlasCompletionItems;
    /// <summary>Anzeigereihenfolge: Index in Items, Überschriften negativ.</summary>
    Order: TArray<Integer>;
    Pattern: string;
    /// <summary>Position der Überschrift „Weitere Einträge“ (#497); -1 ohne.</summary>
    RestFrom: Integer;
    /// <summary>Der Server indiziert noch (#492).</summary>
    Limited: Boolean;
    /// <summary>Aktives Ziel („Win32 · Debug“, #476); '' = keins bekannt.</summary>
    Target: string;
    /// <summary>Hinweis der Fußzeile (#458); '' ohne.</summary>
    Notice: string;
  end;

  /// <summary>Linker und rechter Text der Fußzeile.</summary>
  TAtlasCompletionFooter = record
    Left: string;
    Right: string;
  end;

  TAtlasCompletionTexts = class
  private
    /// <summary>Überschrift aus dem Eintrag nach der Überschrift an APosition.</summary>
    class function NextHeader(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): string; static;
    /// <summary>Gruppe im uses-Abschnitt (#469); '' ohne.</summary>
    class function UsesGroupText(const AGroup: string): string; static;
    /// <summary>Formular (#455), Felder zuweisen (#491), Interface (#466), Exceptions (#483); '' ohne.</summary>
    class function MarkedGroupText(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Menge (#448), erwarteter Typ (#417, #444), nach dem Formular, geerbt (#419).</summary>
    class function TypedGroupText(const AItem: TAtlasCompletionItem; AAfterForm: Boolean): string; static;
    /// <summary>Steht vor APosition eine Komponente des Formulars (#455)?</summary>
    class function AfterForm(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): Boolean; static;
    /// <summary>Ausgeblendete Units, abstrakte Methoden, gleichnamige Bezeichner; '' ohne.</summary>
    class function HiddenText(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Die Tasten, oder das Ziel, sobald Einträge an Bedingungen hängen (#476).</summary>
    class function KeysText(const AList: TAtlasCompletionList): string; static;
    class function HasCondition(const AList: TAtlasCompletionList): Boolean; static;
    /// <summary>Einträge, die zum erwarteten Typ passen (#417), ohne Aktionen.</summary>
    class function FittingCount(const AList: TAtlasCompletionList): Integer; static;
  public
    /// <summary>Text einer Marke (#446).</summary>
    class function TagText(const ATag: TAtlasTag): string; static;
    /// <summary>Detail rechts: im uses-Abschnitt (#469) „bereits im interface-Teil“.</summary>
    class function DetailText(const AItem: TAtlasCompletionItem): string; static;
    /// <summary>Art eines Eintrags in Worten für die Sprachausgabe.</summary>
    class function KindText(AKind: TAtlasItemKind): string; static;
    /// <summary>Text der Überschrift an APosition (geerbt von, Weitere Einträge, …).</summary>
    class function HeaderText(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): string; static;
    /// <summary>Rechts in der Fußzeile: „3 von 84“ bzw. mit erwartetem Typ „3 passend · 84 gesamt“ (#417).</summary>
    class function CountText(const AList: TAtlasCompletionList): string; static;
    /// <summary>Links in der Fußzeile: Hinweis, ausgeblendete Einträge, Tasten oder Ziel (#476).</summary>
    class function FooterLeftText(const AList: TAtlasCompletionList): string; static;
    /// <summary>Beide Texte der Fußzeile je nach Modus (Menge, Absichern, SQL, Typargumente).</summary>
    class function Footer(const AList: TAtlasCompletionList): TAtlasCompletionFooter; static;
    /// <summary>Text der Warnleiste (#457) vor der Zeilenangabe.</summary>
    class function SyntaxLead(ATrust: TAtlasSyntaxTrust): string; static;
    /// <summary>Zeilenangabe der Warnleiste; ALine 0-basiert.</summary>
    class function SyntaxLineText(ALine: Integer): string; static;
    /// <summary>Voller Text einer gekürzten Zeile für den Tooltip (#420).</summary>
    class function TipText(const AItem: TAtlasCompletionItem; const ATags: TAtlasTags): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Sets,
  Atlas.UI.Strings;

{ TAtlasCompletionTexts }

class function TAtlasCompletionTexts.TagText(const ATag: TAtlasTag): string;
begin
  case ATag.Id of
    TAtlasTagId.Recent: Result := TAtlasStrings.Text(TAtlasTextId.TagRecent);
    TAtlasTagId.Frequent: Result := TAtlasStrings.Text(TAtlasTextId.TagFrequent);
    TAtlasTagId.Cycle: Result := TAtlasStrings.Text(TAtlasTextId.UsesCycleTag);
    TAtlasTagId.SameParams: Result := TAtlasStrings.Text(TAtlasTextId.InheritedSameTag);
    TAtlasTagId.Overload: Result := TAtlasStrings.Text(TAtlasTextId.InheritedOverloadTag);
    TAtlasTagId.Active: Result := TAtlasStrings.Text(TAtlasTextId.SameNameActiveTag);
    TAtlasTagId.VariantBranch: Result := TAtlasStrings.Fmt(TAtlasTextId.TagVariantBranch, [ATag.Arg]);
  else
    Result := ATag.Text;
  end;
end;

class function TAtlasCompletionTexts.DetailText(const AItem: TAtlasCompletionItem): string;
begin
  if AItem.UsesElsewhere = 'interface' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UsesInInterface);
  end
  else if AItem.UsesElsewhere = 'implementation' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UsesInImplementation);
  end
  else
  begin
    Result := TAtlasItemPresentation.Detail(AItem);
  end;
end;

class function TAtlasCompletionTexts.KindText(AKind: TAtlasItemKind): string;
begin
  case AKind of
    TAtlasItemKind.Method, TAtlasItemKind.Function_, TAtlasItemKind.Procedure_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindMethod);
    TAtlasItemKind.Constructor_, TAtlasItemKind.Destructor_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindConstructor);
    TAtlasItemKind.Property_, TAtlasItemKind.Event:
      Result := TAtlasStrings.Text(TAtlasTextId.KindProperty);
    TAtlasItemKind.Field:
      Result := TAtlasStrings.Text(TAtlasTextId.KindField);
    TAtlasItemKind.Variable, TAtlasItemKind.Parameter:
      Result := TAtlasStrings.Text(TAtlasTextId.KindVariable);
    TAtlasItemKind.Constant:
      Result := TAtlasStrings.Text(TAtlasTextId.KindConstant);
    TAtlasItemKind.Type_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindType);
    TAtlasItemKind.Class_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindClass);
    TAtlasItemKind.Interface_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindInterface);
    TAtlasItemKind.Record_:
      Result := TAtlasStrings.Text(TAtlasTextId.KindRecord);
    TAtlasItemKind.Enum:
      Result := TAtlasStrings.Text(TAtlasTextId.KindEnum);
    TAtlasItemKind.EnumMember:
      Result := TAtlasStrings.Text(TAtlasTextId.KindEnumMember);
  else
    Result := '';
  end;
end;

class function TAtlasCompletionTexts.HeaderText(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): string;
begin
  // Überschrift einer Gruppe geerbter Member (#419): Klasse des nächsten Eintrags;
  // mit erwartetem Typ (#417, #444) „Passt zu …“ bzw. „Weitere“.
  if AOrder[APosition] = TAtlasRanking.cTypoHeader then
  begin
    // Tippfehler-Treffer (#485).
    Result := TAtlasStrings.Text(TAtlasTextId.DidYouMean);
  end
  else if AOrder[APosition] = TAtlasRanking.cRestHeader then
  begin
    // Rest der Liste ohne Treffer (#497).
    Result := TAtlasStrings.Text(TAtlasTextId.CompletionRestHeader);
  end
  else if (APosition < High(AOrder)) and (AOrder[APosition + 1] >= 0) then
  begin
    Result := NextHeader(AItems, AOrder, APosition);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.InheritedPlain);
  end;
end;

class function TAtlasCompletionTexts.NextHeader(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): string;
var
  mItem: TAtlasCompletionItem;
begin
  mItem := AItems[AOrder[APosition + 1]];
  if AOrder[APosition] = TAtlasRanking.cUnknownHeader then
  begin
    // Unbekannter Name (#471): „TotalCount ist unbekannt“.
    Result := TAtlasStrings.Fmt(TAtlasTextId.UnknownHeader, [mItem.Unknown]);
  end
  else if (APosition = 0) and (mItem.Sender <> '') then
  begin
    // Sender mit Typumwandlung (#480): „Sender ist TButton · btnSave, btnLoad“ über der Liste; weitere
    // Überschriften darin sind die der geerbten Gruppen.
    Result := TAtlasStrings.Fmt(TAtlasTextId.SenderHeader, [mItem.Sender, mItem.SenderOf]);
  end
  else if mItem.TypeParam <> '' then
  begin
    // Typargumente (#450): „T: class · nur Klassen“.
    Result := TAtlasStrings.TypeArgHeading(mItem.TypeParam, mItem.Constraint, mItem.ConstraintHint);
  end
  else
  begin
    Result := UsesGroupText(mItem.UsesGroup);
    if Result = '' then
    begin
      Result := MarkedGroupText(mItem);
    end;
    if Result = '' then
    begin
      Result := TypedGroupText(mItem, AfterForm(AItems, AOrder, APosition));
    end;
  end;
end;

class function TAtlasCompletionTexts.UsesGroupText(const AGroup: string): string;
begin
  // uses-Abschnitt (#469): Projekt, RTL/VCL, Drittanbieter.
  if AGroup = 'project' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UsesGroupProject);
  end
  else if AGroup = 'rtl' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UsesGroupRtl);
  end
  else if AGroup = 'library' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.UsesGroupLibrary);
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasCompletionTexts.MarkedGroupText(const AItem: TAtlasCompletionItem): string;
begin
  if AItem.Form <> '' then
  begin
    // Komponenten aus dem Formular (#455): „Formular frmMain“.
    Result := TAtlasStrings.Fmt(TAtlasTextId.FormHeader, [AItem.Form]);
  end
  else if AItem.Assign then
  begin
    // Alle Felder zuweisen (#491): „Alle Felder zuweisen · TOptions“.
    Result := TAtlasStrings.Fmt(TAtlasTextId.AssignHeader, [AItem.SetOf]);
  end
  else if AItem.Batch then
  begin
    // Interface implementieren (#466): „Fehlende Methoden von IExporter, IFlush“.
    Result := TAtlasStrings.Fmt(TAtlasTextId.BatchHeader, [AItem.SetOf]);
  end
  else if AItem.ExceptionGroup = 'try' then
  begin
    // Exception-Klassen nach "on E: " (#483): „Aus dem try-Block“ und „Allgemein“.
    Result := TAtlasStrings.Text(TAtlasTextId.ExceptionGroupTry);
  end
  else if AItem.ExceptionGroup = 'general' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.ExceptionGroupGeneral);
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasCompletionTexts.TypedGroupText(const AItem: TAtlasCompletionItem; AAfterForm: Boolean): string;
begin
  if AItem.SetOf <> '' then
  begin
    // Mengenmodus (#448): „TAnchors · Menge von TAnchorKind“, bei "X in [" nur „Menge von …“.
    if AItem.ExpectedType.StartsWith('set of ') then
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetHeaderPlain, [AItem.SetOf]);
    end
    else
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.SetHeader, [AItem.ExpectedType, AItem.SetOf]);
    end;
  end
  else if AItem.ExpectedType <> '' then
  begin
    if AItem.Fits then
    begin
      Result := TAtlasStrings.Fmt(TAtlasTextId.FitsType, [AItem.ExpectedType]);
    end
    else
    begin
      Result := TAtlasStrings.Text(TAtlasTextId.OtherGroup);
    end;
  end
  else if AAfterForm then
  begin
    // Direkt nach den Komponenten des Formulars (#455) beginnt die übrige Liste.
    Result := TAtlasStrings.Text(TAtlasTextId.OtherGroup);
  end
  else if AItem.DeclaringClass <> '' then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.InheritedFrom, [AItem.DeclaringClass]);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.InheritedPlain);
  end;
end;

class function TAtlasCompletionTexts.AfterForm(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): Boolean;
begin
  Result := (APosition > 0) and (AOrder[APosition - 1] >= 0) and (AItems[AOrder[APosition - 1]].Form <> '');
end;

class function TAtlasCompletionTexts.HiddenText(const AItems: TAtlasCompletionItems): string;
begin
  if Length(TAtlasItemPresentation.UsesHidden(AItems)) > 0 then
  begin
    // uses-Abschnitt (#469): welche Units schon eingebunden sind und deshalb fehlen.
    Result := TAtlasStrings.UsesHidden(TAtlasItemPresentation.UsesHidden(AItems));
  end
  else if Length(TAtlasItemPresentation.InheritedAbstract(AItems)) > 0 then
  begin
    // Nach "inherited " (#482): welche abstrakten Vorfahrmethoden fehlen.
    Result := TAtlasStrings.InheritedAbstract(TAtlasItemPresentation.InheritedAbstract(AItems));
  end
  else if Length(TAtlasItemPresentation.SameNameHidden(AItems)) > 0 then
  begin
    // Gleichnamige Bezeichner (#475): ausgeblendete FireMonkey-Varianten.
    Result := TAtlasStrings.Fmt(TAtlasTextId.SameNameHiddenFooter,
      [string.Join(', ', TAtlasItemPresentation.SameNameHidden(AItems))]);
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasCompletionTexts.HasCondition(const AList: TAtlasCompletionList): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex in AList.Order do
  begin
    if (mIndex >= 0) and (AList.Items[mIndex].Condition <> '') then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasCompletionTexts.KeysText(const AList: TAtlasCompletionList): string;
begin
  if (AList.Target <> '') and HasCondition(AList) then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.TargetFooter, [AList.Target]);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.FooterKeys);
  end;
end;

class function TAtlasCompletionTexts.FooterLeftText(const AList: TAtlasCompletionList): string;
begin
  // Hinweis zu den Favoriten (#458) hat Vorrang.
  Result := AList.Notice;
  if Result = '' then
  begin
    Result := HiddenText(AList.Items);
  end;
  if Result = '' then
  begin
    Result := KeysText(AList);
  end;
end;

class function TAtlasCompletionTexts.FittingCount(const AList: TAtlasCompletionList): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex in AList.Order do
  begin
    if (mIndex >= 0) and AList.Items[mIndex].Fits and not AList.Items[mIndex].IsAction then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasCompletionTexts.CountText(const AList: TAtlasCompletionList): string;
var
  mFitting: Integer;
begin
  // Mengenmodus (#448): wie viele Werte angehakt sind.
  if TAtlasCompletionSets.Active(AList.Items) then
  begin
    Exit(TAtlasStrings.Fmt(TAtlasTextId.SetChosen, [TAtlasCompletionSets.CheckedCount(AList.Items)]));
  end;
  mFitting := FittingCount(AList);
  if TAtlasRanking.OnlyTypos(AList.Order) or (AList.RestFrom = 0) then
  begin
    // Nur ähnliche Namen (#485) bzw. nur der Rest (#497): kein echter Treffer für das Getippte.
    Result := TAtlasStrings.Fmt(TAtlasTextId.NoMatchesFor, [AList.Pattern]);
  end
  else if AList.RestFrom > 0 then
  begin
    // Treffer, darunter der gedämpfte Rest (#497).
    Result := TAtlasStrings.Fmt(TAtlasTextId.CountHitsRest,
      [TAtlasRanking.ItemCount(Copy(AList.Order, 0, AList.RestFrom)),
      TAtlasRanking.ItemCount(Copy(AList.Order, AList.RestFrom, MaxInt))]);
  end
  else if mFitting > 0 then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.CountFits, [mFitting, TAtlasRanking.ItemCount(AList.Order)]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.CountOf, [TAtlasRanking.ItemCount(AList.Order), Length(AList.Items)]);
  end;
  if AList.Limited then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.CompletionLimited) + ' · ' + Result;
  end;
end;

class function TAtlasCompletionTexts.Footer(const AList: TAtlasCompletionList): TAtlasCompletionFooter;
begin
  Result.Right := CountText(AList);
  if TAtlasCompletionSets.Active(AList.Items) then
  begin
    Result.Left := TAtlasStrings.Text(TAtlasTextId.SetFooterKeys);
  end
  else if TAtlasItemPresentation.Guarding(AList.Items) then
  begin
    // Freigabe absichern (#489).
    Result.Left := TAtlasStrings.Text(TAtlasTextId.GuardFooterKeys);
    Result.Right := '';
  end
  else if TAtlasItemPresentation.DataSource(AList.Items) <> '' then
  begin
    // Feld- und Parameternamen (#461): die SQL-Anweisung als Quellenangabe.
    Result.Left := TAtlasStrings.Fmt(TAtlasTextId.DataSourceFooter, [TAtlasItemPresentation.DataSource(AList.Items)]);
  end
  else if TAtlasItemPresentation.HiddenKinds(AList.Items) <> '' then
  begin
    // Typargumente (#450): „Ausgeblendet: Records, Aufzählungen“.
    Result.Left := TAtlasStrings.TypeArgHidden(TAtlasItemPresentation.HiddenKinds(AList.Items));
  end
  else
  begin
    // Tasten, oder das aktive Ziel bei Einträgen mit Bedingung (#476).
    Result.Left := FooterLeftText(AList);
  end;
end;

class function TAtlasCompletionTexts.SyntaxLead(ATrust: TAtlasSyntaxTrust): string;
begin
  if ATrust = TAtlasSyntaxTrust.Unknown then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SyntaxUnknown);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SyntaxLimited);
  end;
end;

class function TAtlasCompletionTexts.SyntaxLineText(ALine: Integer): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.SyntaxLine, [ALine + 1]);
end;

class function TAtlasCompletionTexts.TipText(const AItem: TAtlasCompletionItem; const ATags: TAtlasTags): string;
var
  mDetail: string;
  mTag: TAtlasTag;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create(AItem.Name);
  try
    mDetail := DetailText(AItem);
    if mDetail <> '' then
    begin
      mBuilder.Append('   ').Append(mDetail);
    end;
    for mTag in ATags do
    begin
      mBuilder.Append('   [').Append(TagText(mTag)).Append(']');
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
