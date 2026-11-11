unit Atlas.Core.Designer.Similar;

// Gleiche Komponenten im Designer auswählen (#738), ohne VCL und Windows.
// Bezug ist eine Komponente des Formulars (die zuerst gewählte); gesucht wird
// nach gleicher Klasse, Klasse samt Nachfahren (bei Mehrfachauswahl ab der
// nächsten gemeinsamen Basisklasse), gleichem Elternelement, Kindern bzw.
// allen Nachkommen eines Containers, gleichem gespeicherten Eigenschaftswert
// und gleichem Ereignis-Handler; dazu „Auswahl umkehren“.
// - Bereich: ganzes Formular oder nur das Elternelement des Bezugs.
// - Ist der Bezug ein Steuerelement, zählen nur Steuerelemente; ist er
//   nichtvisuell, auch die nichtvisuellen.
// - Merge setzt das Ergebnis an die Stelle der Auswahl oder ergänzt sie
//   (Umschalt).

interface

type
  TAtlasSimilarItem = record
    Name: string;
    /// <summary>Klasse zuerst, dann ihre Vorfahren (TEdit, TCustomEdit, TWinControl …).</summary>
    Classes: TArray<string>;
    /// <summary>Name des Elternelements; '' = direkt auf dem Formular bzw. nichtvisuell.</summary>
    ParentName: string;
    Visual: Boolean;
    /// <summary>Gespeicherte Eigenschaften als „Font.Name = 'Tahoma'“.</summary>
    Values: TArray<string>;
    /// <summary>Zugewiesene Ereignis-Handler (Methodennamen).</summary>
    Handlers: TArray<string>;
    Selected: Boolean;
    class function Create(const AName: string; const AClasses: TArray<string>; const AParentName: string;
      AVisual: Boolean): TAtlasSimilarItem; static;
  end;

{$SCOPEDENUMS ON}
  TAtlasSimilarKind = (SameClass, ClassAndDescendants, SameParent, Children, AllChildren, SameValue, SameHandler,
    Invert);
  TAtlasSimilarScope = (Form, Parent);
{$SCOPEDENUMS OFF}

  /// <summary>Anfrage an TAtlasSimilar.Find.</summary>
  TAtlasSimilarQuery = record
    Kind: TAtlasSimilarKind;
    /// <summary>Index des Bezugs in den Komponenten.</summary>
    Reference: Integer;
    /// <summary>Wert („Font.Name = 'Tahoma'“) bzw. Handler bei SameValue und SameHandler.</summary>
    Argument: string;
    Scope: TAtlasSimilarScope;
    class function Create(AKind: TAtlasSimilarKind; AReference: Integer; AScope: TAtlasSimilarScope;
      const AArgument: string = ''): TAtlasSimilarQuery; static;
  end;

  TAtlasSimilar = class
  public
    /// <summary>Erste gewählte Komponente; -1 ohne Auswahl.</summary>
    class function Reference(const AItems: TArray<TAtlasSimilarItem>): Integer; static;
    /// <summary>Nächste gemeinsame Basisklasse der gewählten Komponenten (bzw. die Klasse des Bezugs allein);
    /// '' ohne gemeinsame.</summary>
    class function CommonBase(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer): string; static;
    /// <summary>Indizes der passenden Komponenten in Formularreihenfolge.</summary>
    class function Find(const AItems: TArray<TAtlasSimilarItem>; const AQuery: TAtlasSimilarQuery): TArray<Integer>;
      static;
    /// <summary>Werte von AItem für „Gleicher Eigenschaftswert“: ohne Lage, Größe und TabOrder, die bei jeder
    /// Komponente anders sind.</summary>
    class function OfferedValues(const AItem: TAtlasSimilarItem): TArray<string>; static;
    /// <summary>Neue Auswahl: AHits allein oder, mit AExtend, die bisherige Auswahl samt AHits.</summary>
    class function Merge(const AItems: TArray<TAtlasSimilarItem>; const AHits: TArray<Integer>;
      AExtend: Boolean): TArray<Integer>; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasSimilarItem }

class function TAtlasSimilarItem.Create(const AName: string; const AClasses: TArray<string>;
  const AParentName: string; AVisual: Boolean): TAtlasSimilarItem;
begin
  Result := Default(TAtlasSimilarItem);
  Result.Name := AName;
  Result.Classes := AClasses;
  Result.ParentName := AParentName;
  Result.Visual := AVisual;
end;

{ TAtlasSimilarQuery }

class function TAtlasSimilarQuery.Create(AKind: TAtlasSimilarKind; AReference: Integer; AScope: TAtlasSimilarScope;
  const AArgument: string): TAtlasSimilarQuery;
begin
  Result.Kind := AKind;
  Result.Reference := AReference;
  Result.Scope := AScope;
  Result.Argument := AArgument;
end;

function Contains(const AList: TArray<string>; const AText: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ClassOf(const AItem: TAtlasSimilarItem): string;
begin
  Result := '';
  if Length(AItem.Classes) > 0 then
  begin
    Result := AItem.Classes[0];
  end;
end;

{ TAtlasSimilar }

class function TAtlasSimilar.Reference(const AItems: TArray<TAtlasSimilarItem>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Selected then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasSimilar.CommonBase(const AItems: TArray<TAtlasSimilarItem>; AReference: Integer): string;
var
  mBase: string;
  mItem: TAtlasSimilarItem;
  mCommon: Boolean;
begin
  Result := '';
  if (AReference < 0) or (AReference > High(AItems)) then
  begin
    Exit;
  end;
  // Die erste Klasse in der Kette des Bezugs, die jede gewählte Komponente auch hat.
  for mBase in AItems[AReference].Classes do
  begin
    mCommon := True;
    for mItem in AItems do
    begin
      if mItem.Selected and not Contains(mItem.Classes, mBase) then
      begin
        mCommon := False;
        Break;
      end;
    end;
    if mCommon then
    begin
      Exit(mBase);
    end;
  end;
end;

/// <summary>Ist AParent ein Vorfahr von AItem (Elternkette über die Namen)?</summary>
function HasAncestor(const AItems: TArray<TAtlasSimilarItem>; AItem: Integer; const AParent: string): Boolean;
var
  mName: string;
  mStep, mIndex: Integer;
  mFound: Boolean;
begin
  mName := AItems[AItem].ParentName;
  // Höchstens so viele Schritte wie Komponenten: Ein Ring in den Daten hält nicht auf.
  for mStep := 0 to High(AItems) do
  begin
    if mName = '' then
    begin
      Exit(False);
    end;
    if SameText(mName, AParent) then
    begin
      Exit(True);
    end;
    mFound := False;
    for mIndex := 0 to High(AItems) do
    begin
      if SameText(AItems[mIndex].Name, mName) then
      begin
        mName := AItems[mIndex].ParentName;
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Passt AItem zur Art der Anfrage (ohne Bereich und Sichtbarkeit)?</summary>
function Matches(const AItems: TArray<TAtlasSimilarItem>; AIndex: Integer; const AQuery: TAtlasSimilarQuery;
  const ABase: string): Boolean;
var
  mItem, mReference: TAtlasSimilarItem;
begin
  mItem := AItems[AIndex];
  mReference := AItems[AQuery.Reference];
  case AQuery.Kind of
    TAtlasSimilarKind.SameClass:
      Result := SameText(ClassOf(mItem), ClassOf(mReference));
    TAtlasSimilarKind.ClassAndDescendants:
      Result := (ABase <> '') and Contains(mItem.Classes, ABase);
    TAtlasSimilarKind.SameParent:
      Result := mItem.Visual and SameText(mItem.ParentName, mReference.ParentName);
    TAtlasSimilarKind.Children:
      Result := mItem.Visual and SameText(mItem.ParentName, mReference.Name);
    TAtlasSimilarKind.AllChildren:
      Result := mItem.Visual and HasAncestor(AItems, AIndex, mReference.Name);
    TAtlasSimilarKind.SameValue:
      Result := Contains(mItem.Values, AQuery.Argument);
    TAtlasSimilarKind.SameHandler:
      Result := Contains(mItem.Handlers, AQuery.Argument);
    TAtlasSimilarKind.Invert:
      Result := not mItem.Selected;
  else
    Result := False;
  end;
end;

class function TAtlasSimilar.Find(const AItems: TArray<TAtlasSimilarItem>;
  const AQuery: TAtlasSimilarQuery): TArray<Integer>;
var
  mIndex: Integer;
  mReference: TAtlasSimilarItem;
  mBase: string;
  mInScope: Boolean;
begin
  Result := nil;
  if (AQuery.Reference < 0) or (AQuery.Reference > High(AItems)) then
  begin
    Exit;
  end;
  mReference := AItems[AQuery.Reference];
  mBase := '';
  if AQuery.Kind = TAtlasSimilarKind.ClassAndDescendants then
  begin
    mBase := CommonBase(AItems, AQuery.Reference);
  end;
  for mIndex := 0 to High(AItems) do
  begin
    // Steuerelement als Bezug: nur Steuerelemente; nichtvisueller Bezug: alle.
    if mReference.Visual and not AItems[mIndex].Visual then
    begin
      Continue;
    end;
    // Kinder liegen im Bezug selbst, nicht neben ihm.
    mInScope := (AQuery.Scope = TAtlasSimilarScope.Form) or
      (AQuery.Kind in [TAtlasSimilarKind.Children, TAtlasSimilarKind.AllChildren]) or
      SameText(AItems[mIndex].ParentName, mReference.ParentName);
    if mInScope and Matches(AItems, mIndex, AQuery, mBase) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasSimilar.OfferedValues(const AItem: TAtlasSimilarItem): TArray<string>;
const
  cLayout: array[0..9] of string = ('Left', 'Top', 'Width', 'Height', 'TabOrder', 'ExplicitLeft', 'ExplicitTop',
    'ExplicitWidth', 'ExplicitHeight', 'DesignSize');
var
  mValue, mPath: string;
  mSeparator, mIndex: Integer;
  mLayout: Boolean;
begin
  Result := nil;
  for mValue in AItem.Values do
  begin
    mSeparator := Pos(' = ', mValue);
    mPath := Copy(mValue, 1, mSeparator - 1);
    mLayout := False;
    for mIndex := Low(cLayout) to High(cLayout) do
    begin
      if SameText(mPath, cLayout[mIndex]) then
      begin
        mLayout := True;
        Break;
      end;
    end;
    if not mLayout then
    begin
      Result := Result + [mValue];
    end;
  end;
end;

class function TAtlasSimilar.Merge(const AItems: TArray<TAtlasSimilarItem>; const AHits: TArray<Integer>;
  AExtend: Boolean): TArray<Integer>;
var
  mWanted: TArray<Boolean>;
  mIndex: Integer;
begin
  SetLength(mWanted, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mWanted[mIndex] := AExtend and AItems[mIndex].Selected;
  end;
  for mIndex in AHits do
  begin
    if (mIndex >= 0) and (mIndex <= High(AItems)) then
    begin
      mWanted[mIndex] := True;
    end;
  end;
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if mWanted[mIndex] then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

end.
