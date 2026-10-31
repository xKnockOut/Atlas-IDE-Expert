unit Atlas.Common.Rules.Builtin.Packages;

// Prüfung an Package-Dateien (#46): Units, die implizit ins Package gezogen
// würden, wie die Compilerwarnung W1033. Ausgehend von den Units in contains
// folgt die Regel den uses-Listen (interface und implementation) über den
// Index. Eine Unit ist implizit, wenn sie weder in contains steht noch zu einem
// Package aus requires gehört (TRuleContext.PackageProvides) und als Quelltext
// des Projekts gefunden wird. Bibliotheks-Units, nicht auffindbare Units und
// Packages, deren Inhalt unbekannt ist, ergeben keinen Treffer. Gemeldet wird
// am contains-Eintrag, über den die Unit erreicht wird; die Korrektur nimmt sie
// in contains auf. Ohne Index oder PackageProvides (Linter) schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  ImplicitPackageImportRuleId = 'implicit-package-import';

type
  TImplicitPackageImportRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterPackageRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.PackageReader;

type
  TPending = record
    UnitName: string;
    /// <summary>contains-Eintrag, über den die Unit erreicht wurde.</summary>
    Origin: Integer;
  end;

function FindIndexed(const AContext: TRuleContext; const AUnitName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := AContext.Index.FindUnit(AUnitName, AUnit);
  if not Result and Assigned(AContext.EnsureUnit) and AContext.EnsureUnit(AUnitName) then
    Result := AContext.Index.FindUnit(AUnitName, AUnit);
end;

/// <summary>requires des Packages und, über PackageRequires, die Packages, die diese verlangen: dcc sieht deren
/// Units ebenso (Atlas.Windows → Atlas.Common → Atlas.Text); ohne Doppelte, in Suchreihenfolge.</summary>
function RequiredClosure(const AContext: TRuleContext; const ASource: TPackageSource): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mList: TList<string>;
  mEntry: TPackageEntry;
  mPosition: Integer;
  mRequired: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<string>.Create;
  try
    for mEntry in ASource.Requires do
      if not mSeen.ContainsKey(UpperCase(mEntry.Name)) then
      begin
        mSeen.Add(UpperCase(mEntry.Name), True);
        mList.Add(mEntry.Name);
      end;
    mPosition := 0;
    while Assigned(AContext.PackageRequires) and (mPosition < mList.Count) do
    begin
      for mRequired in AContext.PackageRequires(mList[mPosition]) do
        if not mSeen.ContainsKey(UpperCase(mRequired)) then
        begin
          mSeen.Add(UpperCase(mRequired), True);
          mList.Add(mRequired);
        end;
      Inc(mPosition);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

function TImplicitPackageImportRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ImplicitPackageImportRuleId, TRuleSeverity.Warning,
    'Unit wird implizit ins Package gezogen: weder in contains noch in einem requires-Package (wie W1033).');
end;

procedure TImplicitPackageImportRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Source: TPackageSource;
  Seen: TDictionary<string, Boolean>;
  Pending: TQueue<TPending>;
  Item, Next: TPending;
  Indexed, Used: TUnitIndex;
  Name, Path, Package: string;
  Required: TArray<string>;
  Index: Integer;
  Provided: Boolean;
  Fix: TRuleFix;
begin
  if (AContext.Index = nil) or not Assigned(AContext.PackageProvides) then
    Exit;
  Source := TPackageReader.Read(AContext.Text);
  if not Source.IsPackage or not Source.HasContains then
    Exit;
  Required := RequiredClosure(AContext, Source);
  Seen := TDictionary<string, Boolean>.Create;
  Pending := TQueue<TPending>.Create;
  try
    for Index := 0 to High(Source.Contains) do
    begin
      Seen.AddOrSetValue(UpperCase(Source.Contains[Index].Name), True);
      Item.UnitName := Source.Contains[Index].Name;
      Item.Origin := Index;
      Pending.Enqueue(Item);
    end;
    while Pending.Count > 0 do
    begin
      Item := Pending.Dequeue;
      if Assigned(AContext.Cancelled) and AContext.Cancelled() then
        Exit;
      // Bibliotheks-Units gehören zu Packages der Installation; ihnen wird nicht gefolgt.
      if not FindIndexed(AContext, Item.UnitName, Indexed) or Indexed.Library_ then
        Continue;
      for Name in Indexed.InterfaceUses + Indexed.ImplementationUses do
      begin
        if Seen.ContainsKey(UpperCase(Name)) then
          Continue;
        Seen.Add(UpperCase(Name), True);
        Provided := False;
        for Package in Required do
          if AContext.PackageProvides(Package, Name) <> TRulePackageAnswer.No then
          begin
            Provided := True;
            Break;
          end;
        if Provided or not FindIndexed(AContext, Name, Used) or Used.Library_ then
          Continue;
        Path := Used.FileName;
        if AContext.FileName <> '' then
          Path := ExtractRelativePath(ExtractFilePath(AContext.FileName), Used.FileName);
        Fix := TRuleFix.Create(Format('"%s" in contains aufnehmen', [Name]),
          [TRuleEdit.Create(TTextRange.Create(Source.ContainsEnd, Source.ContainsEnd),
          TPackageReader.ContainsInsertion(Name, Path, TTextLines.LineBreakOf(AContext.Text)))]);
        AReport.Add(Source.Contains[Item.Origin].Range,
          Format('"%s" wird implizit ins Package gezogen: %s verwendet %s, und die Unit steht weder in ' +
          'contains noch in einem requires-Package (W1033).', [Name, Item.UnitName, Name]), [Fix]);
        // Was die implizite Unit verwendet, kommt ebenfalls mit.
        Next.UnitName := Name;
        Next.Origin := Item.Origin;
        Pending.Enqueue(Next);
      end;
    end;
  finally
    Pending.Free;
    Seen.Free;
  end;
end;

procedure RegisterPackageRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TImplicitPackageImportRule.Create);
end;

end.
