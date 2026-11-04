unit Atlas.Common.Editing.GenericLists.Kinds;

// Was eine ungenerische Listenklasse kann (#1105, #1106): TLegacyListKind beschreibt je alter Klasse (TList,
// TObjectList, TStack, TQueue, TObjectStack, TObjectQueue) das generische Gegenstück und ordnet ihre Mitglieder ein.
// TGenericListNames kennt die Namenslisten, die alle Arten teilen (TObject-Mitglieder, skalare Typen, Contnrs-Typen).

interface

type
  /// <summary>Eine ungenerische Listenklasse und ihr generisches Gegenstück (#1105, #1106).</summary>
  TLegacyListKind = record
    /// <summary>Name der alten Klasse, z. B. TList oder TObjectStack.</summary>
    LegacyName: string;
    /// <summary>Name der generischen Klasse ohne Typargument.</summary>
    GenericName: string;
    /// <summary>Unit der alten Klasse ohne Namespace (Classes, Contnrs); Contnrs entfällt, wenn ungenutzt.</summary>
    LegacyUnit: string;
    /// <summary>Mitglieder ohne Elementtyp, z. B. Count, Clear, Delete.</summary>
    Neutral: TArray<string>;
    /// <summary>Mitglieder, die ein Element liefern, z. B. Items, First, Pop.</summary>
    Reads: TArray<string>;
    /// <summary>Mitglieder mit einem Element als Argument: Name=Position ab 0, z. B. Add=0, Insert=1.</summary>
    ElementArgs: TArray<string>;
    /// <summary>Umbenennungen Alt=Neu, z. B. Push=Enqueue.</summary>
    Renames: TArray<string>;
    /// <summary>Mitglieder ohne sicheres Gegenstück: Name=Grund.</summary>
    Unsupported: TArray<string>;
    /// <summary>Argumente für ein Create ohne Argumente, z. B. False; '' = keine.</summary>
    CreateArguments: string;
    /// <summary>Die Elemente müssen Klassen sein (TObjectList&lt;T: class&gt;).</summary>
    ClassOnly: Boolean;
    /// <summary>L[I] steht für L.Items[I].</summary>
    DefaultItems: Boolean;
    /// <summary>TList aus System.Classes.</summary>
    class function PointerList: TLegacyListKind; static;
    /// <summary>TObjectList aus System.Contnrs.</summary>
    class function ObjectList: TLegacyListKind; static;
    /// <summary>TStack aus System.Contnrs.</summary>
    class function Stack: TLegacyListKind; static;
    /// <summary>TQueue aus System.Contnrs.</summary>
    class function Queue: TLegacyListKind; static;
    /// <summary>TObjectStack aus System.Contnrs.</summary>
    class function ObjectStack: TLegacyListKind; static;
    /// <summary>TObjectQueue aus System.Contnrs.</summary>
    class function ObjectQueue: TLegacyListKind; static;
    /// <summary>Alle bekannten Arten.</summary>
    class function All: TArray<TLegacyListKind>; static;
    /// <summary>Art zu einem alten Klassennamen (ohne Unit-Präfix); False, wenn unbekannt.</summary>
    class function Find(const ALegacyName: string; out AKind: TLegacyListKind): Boolean; static;
    /// <summary>AName ist ein Mitglied ohne Elementtyp.</summary>
    function IsNeutral(const AName: string): Boolean;
    /// <summary>AName liefert ein Element.</summary>
    function IsRead(const AName: string): Boolean;
    /// <summary>AName ist neutral oder liefert ein Element (Mitglied ohne Element-Argument).</summary>
    function IsReadOrNeutral(const AName: string): Boolean;
    /// <summary>AName ist ein bekanntes Mitglied mit Gegenstück (neutral, lesend oder mit Element-Argument).</summary>
    function IsKnown(const AName: string): Boolean;
    /// <summary>AName nimmt ein Element; APosition ist dessen Argument ab 0.</summary>
    function ElementArgument(const AName: string; out APosition: Integer): Boolean;
    /// <summary>AName heißt generisch anders; ANewName ist der neue Name.</summary>
    function RenameOf(const AName: string; out ANewName: string): Boolean;
    /// <summary>AName hat kein sicheres Gegenstück; AReason nennt es.</summary>
    function UnsupportedReason(const AName: string; out AReason: string): Boolean;
    /// <summary>Generischer Typtext mit Elementtyp, z. B. TList&lt;TPosition&gt;.</summary>
    function GenericText(const AItemType: string): string;
    /// <summary>AName ist die Unit der alten Klasse, mit oder ohne System-Präfix.</summary>
    function IsLegacyUnit(const AName: string): Boolean;
  end;

  /// <summary>Namenslisten, die alle Listenarten teilen.</summary>
  TGenericListNames = record
    /// <summary>Mitglied von TObject: an einer Liste ohne Typbezug, an einem Element einer Objektliste ohne Cast
    /// erlaubt.</summary>
    class function IsObjectMember(const AName: string): Boolean; static;
    /// <summary>Elemente dieses Typs sind keine Objekte bzw. Zeiger desselben Typs.</summary>
    class function IsScalarType(const AName: string): Boolean; static;
    /// <summary>Typ aus System.Contnrs; nennt die Unit keinen davon mehr, entfällt Contnrs aus den uses.</summary>
    class function IsContnrsType(const AName: string): Boolean; static;
    /// <summary>Eintrag AName in einer Liste aus Name bzw. Name=Wert; AValue ist der Wert ('' ohne).</summary>
    class function ValueOf(const AName: string; const AList: TArray<string>; out AValue: string): Boolean; static;
  end;

const
  /// <summary>Unit der generischen Klassen.</summary>
  cGenericListUnit = 'System.Generics.Collections';

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cObjectMembers: array[0..12] of string = ('Free', 'Destroy', 'DisposeOf', 'ClassName', 'ClassType', 'ClassInfo',
    'InstanceSize', 'InheritsFrom', 'ToString', 'GetHashCode', 'Equals', 'ClassParent', 'UnitName');
  cScalarTypes: array[0..21] of string = ('Pointer', 'Integer', 'Cardinal', 'NativeInt', 'NativeUInt', 'Int64',
    'UInt64', 'LongInt', 'LongWord', 'IntPtr', 'UIntPtr', 'DWORD', 'THandle', 'Byte', 'Word', 'ShortInt',
    'SmallInt', 'Int32', 'UInt32', 'PChar', 'PAnsiChar', 'PWideChar');
  cContnrsTypes: array[0..21] of string = ('TObjectList', 'TComponentList', 'TClassList', 'TOrderedList', 'TStack',
    'TQueue', 'TObjectStack', 'TObjectQueue', 'TCustomBucketList', 'TBucketList', 'TObjectBucketList',
    'TBucketItem', 'TBucketItemArray', 'TBucket', 'TBucketArray', 'TBucketProc', 'TBucketEvent',
    'TBucketListSizes', 'TListBucket', 'TBucketListBucket', 'TComponentListNexus', 'TComponentListNexusEvent');

function CommonNeutral: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := Low(cObjectMembers) to High(cObjectMembers) do
  begin
    Result := Result + [cObjectMembers[mIndex]];
  end;
end;

{ TLegacyListKind }

class function TLegacyListKind.PointerList: TLegacyListKind;
begin
  Result := Default(TLegacyListKind);
  Result.LegacyName := 'TList';
  Result.GenericName := 'TList';
  Result.LegacyUnit := 'Classes';
  Result.Neutral := CommonNeutral + ['Count', 'Capacity', 'Clear', 'Delete', 'Exchange', 'Move'];
  Result.Reads := ['Items', 'First', 'Last', 'Extract', 'ExtractItem'];
  Result.ElementArgs := ['Add=0', 'Insert=1', 'Extract=0', 'Remove=0', 'IndexOf=0', 'ExtractItem=0',
    'RemoveItem=0', 'IndexOfItem=0'];
  Result.Unsupported := ['Sort=Sort mit TListSortCompare', 'SortList=SortList mit TListSortCompareFunc',
    'Assign=Assign mit TListAssignOp', 'List=List-Property (PPointerList)', 'Expand=Expand',
    'Pack=Pack entfernt nil-Einträge anders', 'Grow=Grow', 'Error=Error'];
  Result.DefaultItems := True;
end;

class function TLegacyListKind.ObjectList: TLegacyListKind;
begin
  Result := PointerList;
  Result.LegacyName := 'TObjectList';
  Result.GenericName := 'TObjectList';
  Result.LegacyUnit := 'Contnrs';
  Result.Neutral := Result.Neutral + ['OwnsObjects'];
  Result.Unsupported := Result.Unsupported + ['FindInstanceOf=FindInstanceOf'];
  Result.ClassOnly := True;
end;

class function TLegacyListKind.Stack: TLegacyListKind;
begin
  Result := Default(TLegacyListKind);
  Result.LegacyName := 'TStack';
  Result.GenericName := 'TStack';
  Result.LegacyUnit := 'Contnrs';
  Result.Neutral := CommonNeutral + ['Count'];
  Result.Reads := ['Pop', 'Peek'];
  Result.ElementArgs := ['Push=0'];
  Result.Unsupported := ['AtLeast=AtLeast', 'List=List-Property (TList)'];
end;

class function TLegacyListKind.Queue: TLegacyListKind;
begin
  Result := Stack;
  Result.LegacyName := 'TQueue';
  Result.GenericName := 'TQueue';
  Result.Reads := ['Pop', 'Peek'];
  Result.Renames := ['Push=Enqueue', 'Pop=Dequeue'];
end;

class function TLegacyListKind.ObjectStack: TLegacyListKind;
begin
  Result := Stack;
  Result.LegacyName := 'TObjectStack';
  Result.GenericName := 'TObjectStack';
  // TObjectStack<T>.Pop ist eine Prozedur; Extract liefert das Element ohne Freigabe.
  Result.Renames := ['Pop=Extract'];
  // Die generischen Klassen besitzen ihre Objekte, die aus Contnrs nicht.
  Result.CreateArguments := 'False';
  Result.ClassOnly := True;
end;

class function TLegacyListKind.ObjectQueue: TLegacyListKind;
begin
  Result := ObjectStack;
  Result.LegacyName := 'TObjectQueue';
  Result.GenericName := 'TObjectQueue';
  Result.Renames := ['Push=Enqueue', 'Pop=Extract'];
end;

class function TLegacyListKind.All: TArray<TLegacyListKind>;
begin
  Result := TArray<TLegacyListKind>.Create(PointerList, ObjectList, Stack, Queue, ObjectStack, ObjectQueue);
end;

class function TLegacyListKind.Find(const ALegacyName: string; out AKind: TLegacyListKind): Boolean;
var
  mKind: TLegacyListKind;
begin
  for mKind in All do
  begin
    if SameText(mKind.LegacyName, ALegacyName) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := Default(TLegacyListKind);
  Result := False;
end;

function TLegacyListKind.IsNeutral(const AName: string): Boolean;
var
  mValue: string;
begin
  Result := TGenericListNames.ValueOf(AName, Neutral, mValue);
end;

function TLegacyListKind.IsRead(const AName: string): Boolean;
var
  mValue: string;
begin
  Result := TGenericListNames.ValueOf(AName, Reads, mValue);
end;

function TLegacyListKind.IsReadOrNeutral(const AName: string): Boolean;
begin
  Result := IsRead(AName) or IsNeutral(AName);
end;

function TLegacyListKind.IsKnown(const AName: string): Boolean;
var
  mPosition: Integer;
begin
  Result := IsReadOrNeutral(AName) or ElementArgument(AName, mPosition);
end;

function TLegacyListKind.ElementArgument(const AName: string; out APosition: Integer): Boolean;
var
  mValue: string;
begin
  Result := TGenericListNames.ValueOf(AName, ElementArgs, mValue);
  APosition := StrToIntDef(mValue, 0);
end;

function TLegacyListKind.RenameOf(const AName: string; out ANewName: string): Boolean;
begin
  Result := TGenericListNames.ValueOf(AName, Renames, ANewName);
end;

function TLegacyListKind.UnsupportedReason(const AName: string; out AReason: string): Boolean;
begin
  Result := TGenericListNames.ValueOf(AName, Unsupported, AReason);
end;

function TLegacyListKind.GenericText(const AItemType: string): string;
begin
  Result := GenericName + '<' + AItemType + '>';
end;

function TLegacyListKind.IsLegacyUnit(const AName: string): Boolean;
begin
  Result := SameText(AName, LegacyUnit) or SameText(AName, 'System.' + LegacyUnit);
end;

{ TGenericListNames }

class function TGenericListNames.IsObjectMember(const AName: string): Boolean;
begin
  Result := MatchText(AName, cObjectMembers);
end;

class function TGenericListNames.IsScalarType(const AName: string): Boolean;
begin
  Result := MatchText(AName, cScalarTypes);
end;

class function TGenericListNames.IsContnrsType(const AName: string): Boolean;
begin
  Result := MatchText(AName, cContnrsTypes);
end;

class function TGenericListNames.ValueOf(const AName: string; const AList: TArray<string>;
  out AValue: string): Boolean;
var
  mEntry: string;
  mSeparator: Integer;
begin
  AValue := '';
  for mEntry in AList do
  begin
    mSeparator := Pos('=', mEntry);
    if (mSeparator = 0) and SameText(mEntry, AName) then
    begin
      Exit(True);
    end;
    if (mSeparator > 0) and SameText(Copy(mEntry, 1, mSeparator - 1), AName) then
    begin
      AValue := Copy(mEntry, mSeparator + 1, MaxInt);
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
