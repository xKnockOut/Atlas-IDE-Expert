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
  Atlas.UI.Strings,
  Atlas.UI.Completion.Strings;

{ TAtlasCompletionTexts }

class function TAtlasCompletionTexts.TagText(const ATag: TAtlasTag): string;
begin
  case ATag.Id of
    TAtlasTagId.Recent: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.TagRecent);
    TAtlasTagId.Frequent: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.TagFrequent);
    TAtlasTagId.Cycle: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesCycleTag);
    TAtlasTagId.SameParams: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.InheritedSameTag);
    TAtlasTagId.Overload: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.InheritedOverloadTag);
    TAtlasTagId.Active: Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.SameNameActiveTag);
    TAtlasTagId.VariantBranch: Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.TagVariantBranch,
      [ATag.Arg]);
  else
    Result := ATag.Text;
  end;
end;

class function TAtlasCompletionTexts.DetailText(const AItem: TAtlasCompletionItem): string;
begin
  if AItem.UsesElsewhere = 'interface' then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesInInterface);
  end
  else if AItem.UsesElsewhere = 'implementation' then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesInImplementation);
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
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.DidYouMean);
  end
  else if AOrder[APosition] = TAtlasRanking.cRestHeader then
  begin
    // Rest der Liste ohne Treffer (#497).
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.CompletionRestHeader);
  end
  else if (APosition < High(AOrder)) and (AOrder[APosition + 1] >= 0) then
  begin
    Result := NextHeader(AItems, AOrder, APosition);
  end
  else
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.InheritedPlain);
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
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.UnknownHeader, [mItem.Unknown]);
  end
  else if (APosition = 0) and (mItem.Sender <> '') then
  begin
    // Sender mit Typumwandlung (#480): „Sender ist TButton · btnSave, btnLoad“ über der Liste; weitere
    // Überschriften darin sind die der geerbten Gruppen.
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SenderHeader, [mItem.Sender, mItem.SenderOf]);
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
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesGroupProject);
  end
  else if AGroup = 'rtl' then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesGroupRtl);
  end
  else if AGroup = 'library' then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.UsesGroupLibrary);
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
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.FormHeader, [AItem.Form]);
  end
  else if AItem.Assign then
  begin
    // Alle Felder zuweisen (#491): „Alle Felder zuweisen · TOptions“.
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.AssignHeader, [AItem.SetOf]);
  end
  else if AItem.Batch then
  begin
    // Interface implementieren (#466): „Fehlende Methoden von IExporter, IFlush“.
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.BatchHeader, [AItem.SetOf]);
  end
  else if AItem.ExceptionGroup = 'try' then
  begin
    // Exception-Klassen nach "on E: " (#483): „Aus dem try-Block“ und „Allgemein“.
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.ExceptionGroupTry);
  end
  else if AItem.ExceptionGroup = 'general' then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.ExceptionGroupGeneral);
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
      Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SetHeaderPlain, [AItem.SetOf]);
    end
    else
    begin
      Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SetHeader, [AItem.ExpectedType, AItem.SetOf]);
    end;
  end
  else if AItem.ExpectedType <> '' then
  begin
    if AItem.Fits then
    begin
      Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.FitsType, [AItem.ExpectedType]);
    end
    else
    begin
      Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.OtherGroup);
    end;
  end
  else if AAfterForm then
  begin
    // Direkt nach den Komponenten des Formulars (#455) beginnt die übrige Liste.
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.OtherGroup);
  end
  else if AItem.DeclaringClass <> '' then
  begin
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.InheritedFrom, [AItem.DeclaringClass]);
  end
  else
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.InheritedPlain);
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
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SameNameHiddenFooter,
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
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.TargetFooter, [AList.Target]);
  end
  else
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.FooterKeys);
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
    Exit(TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SetChosen,
      [TAtlasCompletionSets.CheckedCount(AList.Items)]));
  end;
  mFitting := FittingCount(AList);
  if TAtlasRanking.OnlyTypos(AList.Order) or (AList.RestFrom = 0) then
  begin
    // Nur ähnliche Namen (#485) bzw. nur der Rest (#497): kein echter Treffer für das Getippte.
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.NoMatchesFor, [AList.Pattern]);
  end
  else if AList.RestFrom > 0 then
  begin
    // Treffer, darunter der gedämpfte Rest (#497).
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.CountHitsRest,
      [TAtlasRanking.ItemCount(Copy(AList.Order, 0, AList.RestFrom)),
      TAtlasRanking.ItemCount(Copy(AList.Order, AList.RestFrom, MaxInt))]);
  end
  else if mFitting > 0 then
  begin
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.CountFits, [mFitting,
      TAtlasRanking.ItemCount(AList.Order)]);
  end
  else
  begin
    Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.CountOf, [TAtlasRanking.ItemCount(AList.Order),
      Length(AList.Items)]);
  end;
  if AList.Limited then
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.CompletionLimited) + ' · ' + Result;
  end;
end;

class function TAtlasCompletionTexts.Footer(const AList: TAtlasCompletionList): TAtlasCompletionFooter;
begin
  Result.Right := CountText(AList);
  if TAtlasCompletionSets.Active(AList.Items) then
  begin
    Result.Left := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.SetFooterKeys);
  end
  else if TAtlasItemPresentation.Guarding(AList.Items) then
  begin
    // Freigabe absichern (#489).
    Result.Left := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.GuardFooterKeys);
    Result.Right := '';
  end
  else if TAtlasItemPresentation.DataSource(AList.Items) <> '' then
  begin
    // Feld- und Parameternamen (#461): die SQL-Anweisung als Quellenangabe.
    Result.Left := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.DataSourceFooter,
      [TAtlasItemPresentation.DataSource(AList.Items)]);
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
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.SyntaxUnknown);
  end
  else
  begin
    Result := TAtlasCompletionStrings.Text(TAtlasCompletionTextId.SyntaxLimited);
  end;
end;

class function TAtlasCompletionTexts.SyntaxLineText(ALine: Integer): string;
begin
  Result := TAtlasCompletionStrings.Fmt(TAtlasCompletionTextId.SyntaxLine, [ALine + 1]);
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
