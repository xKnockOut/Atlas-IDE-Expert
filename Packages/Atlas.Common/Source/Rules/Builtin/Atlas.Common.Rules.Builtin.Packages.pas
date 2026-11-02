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
  begin
    Result := AContext.Index.FindUnit(AUnitName, AUnit);
  end;
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
    begin
      if not mSeen.ContainsKey(UpperCase(mEntry.Name)) then
      begin
        mSeen.Add(UpperCase(mEntry.Name), True);
        mList.Add(mEntry.Name);
      end;
    end;
    mPosition := 0;
    while Assigned(AContext.PackageRequires) and (mPosition < mList.Count) do
    begin
      for mRequired in AContext.PackageRequires(mList[mPosition]) do
      begin
        if not mSeen.ContainsKey(UpperCase(mRequired)) then
        begin
          mSeen.Add(UpperCase(mRequired), True);
          mList.Add(mRequired);
        end;
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
  begin
    Exit;
  end;
  Source := TPackageReader.Read(AContext.Text);
  if not Source.IsPackage or not Source.HasContains then
  begin
    Exit;
  end;
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
      begin
        Exit;
      end;
      // Bibliotheks-Units gehören zu Packages der Installation; ihnen wird nicht gefolgt.
      if not FindIndexed(AContext, Item.UnitName, Indexed) or Indexed.Library_ then
      begin
        Continue;
      end;
      for Name in Indexed.InterfaceUses + Indexed.ImplementationUses do
      begin
        if Seen.ContainsKey(UpperCase(Name)) then
        begin
          Continue;
        end;
        Seen.Add(UpperCase(Name), True);
        Provided := False;
        for Package in Required do
        begin
          if AContext.PackageProvides(Package, Name) <> TRulePackageAnswer.No then
          begin
            Provided := True;
            Break;
          end;
        end;
        if Provided or not FindIndexed(AContext, Name, Used) or Used.Library_ then
        begin
          Continue;
        end;
        Path := Used.FileName;
        if AContext.FileName <> '' then
        begin
          Path := ExtractRelativePath(ExtractFilePath(AContext.FileName), Used.FileName);
        end;
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
