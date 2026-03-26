Resolving dependencies...
#### hitch <- parallel

:| sire
:| stew_misc
:| set
:| tab
:| stew_datatype
:| stew

= (packIndexNode [keys nodes] hh)
| MkPin (1 keys nodes hh)

> Row a > Maybe (a , Row a)
= (rowUncons r)
| if (null r) NONE
| SOME [(idx 0 r) (drop 1 r)]

=?= NONE (rowUncons [])
=?= (SOME [0 [1 2 3]]) (rowUncons [0 1 2 3])

> Row a > Maybe (Row a , a)
= (rowUnsnoc r)
@ l | len r
| Ifz l NONE
@ minusOne | dec l
| SOME [(take minusOne r) (idx minusOne r)]

=?= NONE (rowUnsnoc [])
=?= (SOME [[0 1 2] 3]) (rowUnsnoc [0 1 2 3])

# record TreeFun
| TREE_FUN
* mkNode : Any
* mkLeaf : Any
* caseNode : Any
* leafInsert : Any
* leafMerge : Any
* leafLength : Any
* leafSplitAt : Any
* leafFirstKey : Any
* leafEmpty : Any
* leafDelete : Any
* hhMerge : Any
* hhLength : Any
* hhSplit : Any
* hhEmpty : Any
* hhDelete : Any

# data HitchNode
- INDEXNODE idx/Any hh/Any
- LEAFNODE leaf/Any

abstype#(Index k v)

abstype#(LazyIndex k v)

> Index k v
= emptyIndex [[] []]

> Index k v > k > Index k v > Index k v
= (mergeIndex [lKeys lVals] middle [rKeys rVals])
[(cat [lKeys [middle] rKeys]) (weld lVals rVals)]

([[5] [%a %b]] =?= mergeIndex [[] ["a"]] 5 [[] ["b"]])

> v > Index k v
= (singletonIndex val) [[] [val]]

> Index k v > Maybe v
= (fromSingletonIndex [_ vals])
| if (eql 1 (len vals)) (get vals 0) 0

> Index k v > Nat
= (indexKeyLen [keys _])
| len keys

> Index k v > Nat
= (indexValLen [_ vals])
| len vals

> Nat > Index k v > (Index k v , k , Index k v)
= (splitIndexAt numLeftKeys [keys vals])
@ leftKeys | take numLeftKeys keys
@ middleKeyAndRightKey | drop numLeftKeys keys
@ numPlusOne | Inc numLeftKeys
@ leftVals | take numPlusOne vals
@ rightVals | drop numPlusOne vals
| Ifz (len middleKeyAndRightKey) (Die %splitIndexAtEmpty)
@ middleKey | get middleKeyAndRightKey 0
@ rightKeys | drop 1 middleKeyAndRightKey
[[leftKeys leftVals] middleKey [rightKeys rightVals]]

=?= [[[] [[%a]]] %b [[] [[%b]]]]
  | splitIndexAt 0 [["b"] [["a"] ["b"]]]

> TreeFun > Nat > Index k v > Index k v
= (extendIndex treeFun maxIndexKeys idx)
@ TREE_FUN(.. ) treeFun
@ maxIndexVals | Inc maxIndexKeys
^ _ idx
? (loop idx)
@ numVals | **indexValLen idx
| if (lte numVals maxIndexVals) | **singletonIndex | mkNode idx hhEmpty
| if
  (lte numVals | mul 2 maxIndexVals)
  @ pos | dec | div numVals 2
  @ [lIdx middleKey rIdx] | splitIndexAt pos idx
  @ !leftNode | mkNode lIdx hhEmpty
  @ !rightNode | mkNode rIdx hhEmpty
  [[middleKey] [leftNode rightNode]]
@ [lIdx middleKey rIdx] | splitIndexAt maxIndexVals idx
@ ls | **singletonIndex | mkNode lIdx hhEmpty
| mergeIndex ls middleKey | loop rIdx

= (valView key [keys vals])
@ [leftKeys rightKeys] | span a&(lte a key) keys
@ n | len leftKeys
@ [leftVals valAndRightVals] | splitAt n vals
| maybeCase
      | rowUncons valAndRightVals
  | Die "valView: can't split empty index"
& [val rightVals]
[[leftKeys leftVals rightKeys rightVals] val]

= (leftView [leftKeys leftVals rightKeys rightVals])
| maybeCase (rowUnsnoc leftVals) NONE
& [leftVals leftVal]
| maybeCase (rowUnsnoc leftKeys) NONE
& [leftKeys leftKey]
@ newCtx [leftKeys leftVals rightKeys rightVals]
| SOME [newCtx leftVal leftKey]

= (rightView [leftKeys leftVals rightKeys rightVals])
| maybeCase (rowUncons rightVals) NONE
& [rightVal rightVals]
| maybeCase (rowUncons rightKeys) NONE
& [rightKey rightKeys]
@ newCtx [leftKeys leftVals rightKeys rightVals]
| SOME [rightKey rightVal newCtx]

= (putVal [leftKeys leftVals rightKeys rightVals] val)
  ++ weld leftKeys rightKeys
  ++ cat [leftVals [val] rightVals]

= (putIdx [leftKeys leftVals rightKeys rightVals] [keys vals])
  ++ cat [leftKeys keys rightKeys]
  ++ cat [leftVals vals rightVals]

= (findSubnodeByKey key [keys vals])
| get vals
@ b | searchSet key keys
@ found | mod b 2
@ idx | rsh b 1
| add found idx

> TreeFun > Nat > Index k n
= (splitLeafMany treeFun maxLeafItems items)
@ TREE_FUN(.. ) treeFun
@ itemLen | leafLength items
| if (lte itemLen maxLeafItems) | **singletonIndex | mkLeaf items
| if
  (lte itemLen | mul 2 maxLeafItems)
  @ numLeft | div itemLen 2
  @ [lLeaf rLeaf] | leafSplitAt numLeft items
  @ rightFirstItem | leafFirstKey rLeaf
  [[rightFirstItem] [(mkLeaf lLeaf) (mkLeaf rLeaf)]]
@ (fixup [keys vals]) [keys (map mkLeaf vals)]
^ fixup (_ items NIL NIL)
? (loop items keys leafs)
@ itemLen | leafLength items
| if
  (gth itemLen | mul 2 maxLeafItems)
  @ [leaf rem] | leafSplitAt maxLeafItems items
  @ key | leafFirstKey rem
  | loop rem (CONS key keys) (CONS leaf leafs)
| if (gth itemLen maxLeafItems)
  @ numLeft | div itemLen 2
  @ [left right] | leafSplitAt numLeft items
  @ key | leafFirstKey right
  | loop leafEmpty (CONS key keys) (CONS right (CONS left leafs))
| Ifz itemLen [(streamRev keys) (streamRev leafs)]
| Die %leafConstraintViolation

# record TreeConfig
| TREE_CONFIG
* minFanout : Any
* maxFanout : Any
* minIdxKeys : Any
* maxIdxKeys : Any
* minLeafItems : Any
= maxLeafItems : Any
* maxHitchhikers : Any

= twoThreeConfig
@ minFanout 2
@ maxFanout | dec | mul 2 minFanout
| TREE_CONFIG
* minFanout
* maxFanout
* dec minFanout
* dec maxFanout
* minFanout
* maxFanout
* minFanout

= largeConfig
@ minFanout 64
@ maxFanout | dec | mul 2 minFanout
| TREE_CONFIG
* minFanout
* maxFanout
* dec minFanout
* dec maxFanout
* minFanout
* maxFanout
* minFanout

= (fixup treeConfig treeFun index)
@ TREE_CONFIG(.. ) treeConfig
@ !newRootNode | fromSingletonIndex index
| Ifz newRootNode
  @ !index | extendIndex treeFun maxLeafItems index
  | fixup treeConfig treeFun index
newRootNode

= (downSplit treeFun l hh)
: key keys < listCase l ~[hh]
@ TREE_FUN(.. ) treeFun
@ [!toAdd !rest] | hhSplit key hh
| CONS toAdd | downSplit treeFun keys rest

= (joinIndex kl il)
# case kl
- NIL
  # case il
  - NIL | (NIL , NIL)
  - CONS [keys vals] _ | (listFromRow keys , ~[vals])
- CONS k ks
  # case il
  - NIL (Die "missing index in joinIndex")
  - CONS [keys vals] ts
    @ [keyrest valrest] | joinIndex ks ts
    @ !kout | listWeld (listFromRow keys) (CONS k keyrest)
    @ !vout | CONS vals valrest
    [kout vout]

= (downPush insertRec treeConfig treeFun [hh node])
  @ TREE_FUN(.. ) treeFun
  | Ifz (hhLength hh) | **singletonIndex node
  | insertRec treeConfig treeFun hh node

= (distributeDownwards insertRec treeConfig treeFun hitchhikers index)
@ TREE_FUN(.. ) treeFun
| Ifz (hhLength hitchhikers) index
@ [keys vals] index
@ keyList | listFromRow keys
@ splitHH | downSplit treeFun keyList hitchhikers
@ indexList
  | listMap (downPush insertRec treeConfig treeFun)
  | listZip splitHH
  | listFromRow vals
@ [!lkeys !lvals] | joinIndex keyList indexList
[(stream lkeys) (cat | stream lvals)]

= (insertRec treeConfig treeFun toAdd node)
@ TREE_CONFIG(.. ) treeConfig
@ TREE_FUN(.. ) treeFun
# case (caseNode node)
- INDEXNODE children hitchhikers
  @ !merged | hhMerge hitchhikers toAdd
  | if
    (gth (hhLength merged) maxHitchhikers)
    @ !distrib
      | distributeDownwards insertRec treeConfig treeFun merged children
    | extendIndex treeFun maxLeafItems distrib
  | else | **singletonIndex | mkNode children merged
- LEAFNODE items
  @ !inserted (leafInsert items toAdd)
  | splitLeafMany treeFun maxLeafItems inserted

distributeDownwards=(distributeDownwards insertRec)

= (splitHitchhikersByKeys treeFun keys hh)
@ TREE_FUN(.. ) treeFun
@ l | len keys
^ unfoldr _ [0 hh]
& [i hh]
| if (eql i l) | (hh , [Inc-i hhEmpty])
| if (gth i l) | 0
@ [!cur !rest] | hhSplit (idx i keys) hh
| (cur , [Inc-i rest])

= (getLeafRow treeFun node)
@ TREE_FUN(.. ) treeFun
^ _ hhEmpty node
? (go_openTreeFun hh node)
# case (caseNode node)
- LEAFNODE leaves @ !item (leafInsert leaves hh)
                  [item]
- INDEXNODE [keys vals] hitchhikers
  @ !merged (hhMerge hitchhikers hh)
  @ splitHH | splitHitchhikersByKeys treeFun keys merged
  | cat
  | map [hh node]&(go_openTreeFun hh node) | zip splitHH vals

= (nodeNeedsMerge config treeFun node)
@ TREE_CONFIG(.. ) config
@ TREE_FUN(.. ) treeFun
# case (caseNode node)
- INDEXNODE index hitchhikers | lth (indexKeyLen index) minIdxKeys
- LEAFNODE leaves | lth (leafLength leaves) minLeafItems

= (mergeNodes config treeFun left middleKey right)
@ TREE_CONFIG(.. ) config
@ TREE_FUN(.. ) treeFun
# case (caseNode left)
- INDEXNODE leftIdx leftHH
  # case (caseNode right)
  - INDEXNODE rightIdx rightHH
    @ !left
      | distributeDownwards config treeFun leftHH leftIdx
    @ !right
      | distributeDownwards config treeFun rightHH rightIdx
    @ !merged | mergeIndex left middleKey right
    | extendIndex treeFun maxIdxKeys merged
  - LEAFNODE _ | Die %nodeMismatch
- LEAFNODE leftLeaf
  # case (caseNode right)
  - LEAFNODE rightLeaf
    @ !merged | leafMerge leftLeaf rightLeaf
    | splitLeafMany treeFun maxLeafItems merged
  - INDEXNODE _ _ | Die %nodeMismatch

(**maybeCaseBack mb som non)=(maybeCase mb non som)

= (deleteRec config treeFun key mybV node)
@ TREE_CONFIG(.. ) config
@ TREE_FUN(.. ) treeFun
# case (caseNode node)
- LEAFNODE leaves | mkLeaf | leafDelete key mybV leaves
- INDEXNODE index hitchhikers
  @ [ctx child] | valView key index
  @ newChild | deleteRec config treeFun key mybV child
  @ childNeedsMerge | nodeNeedsMerge config treeFun newChild
  @ prunedHH | hhDelete key mybV hitchhikers
  | if
        | not childNeedsMerge
    | mkNode (putVal ctx newChild) prunedHH
  | maybeCaseBack
        | rightView ctx
    & [rKey rChild rCtx]
    | mkNode
      | putIdx rCtx | mergeNodes config treeFun newChild rKey rChild
    prunedHH
  | maybeCaseBack
        | leftView ctx
    & [lCtx lChild lKey]
    | mkNode
      | putIdx lCtx | mergeNodes config treeFun lChild lKey newChild
    prunedHH
  | Die "deleteRec: node with single child"

abstype#(HSet a)

abstype#(HMap k v)

abstype#(HSetMap k v)

(hhDeleteKey k _ t)=(tabDel k t)

= (hmEmpty config) | [config 0]

= (hmCaseNode pinnedNode)
@ !node (PinItem pinnedNode)
| Ifz (1 == Hd node) (LEAFNODE node)
@ [keys nodes hh] node
| INDEXNODE [keys nodes] hh

= (hmSingleton config k v)
@ node | MkPin | tabSing k v
[config node]

(tabUnionRightBiased x y)=(tabUnion y x)

= hhMapTF
  ++ packIndexNode
  ++ MkPin
  ++ hmCaseNode
  ++ tabUnionRightBiased
  ++ tabUnionRightBiased
  ++ tabLen
  ++ tabSplitAt
  ++ tabMinKey
  ++ #[]
  ++ hhDeleteKey
  ++ tabUnionRightBiased
  ++ tabLen
  ++ tabSplitLT
  ++ #[]
  ++ hhDeleteKey

= (hmSize [config r])
| Ifz r 0
| sumOf tabLen
| getLeafRow hhMapTF r

= (hmKeys [config top])
| Ifz top %[]
| map tabKeysRow
| getLeafRow hhMapTF top

= (hmInsert k v [config top])
@ p | tabSing k v
| Ifz top | hmSingleton config k v
@ !index | insertRec config hhMapTF p top
@ !fixed
      | fixup config hhMapTF index
  ++ config
  ++ fixed

= (hmInsertMany tab [config top])
| if
    | tabIsEmpty tab
  [config top]
@ TREE_CONFIG(.. ) config
@ !index
  | Ifz top | splitLeafMany hhMapTF maxLeafItems tab
  | insertRec config hhMapTF tab top
@ !fixed
      | fixup config hhMapTF index
  ++ config
  ++ fixed

= (hmDelete k [config r])
| Ifz r [config r]
@ newRootNode | deleteRec config hhMapTF k NONE r
# case (hmCaseNode newRootNode)
- LEAFNODE leaves
  ++ config
  ++ if (tabIsEmpty leaves) NONE (SOME newRootNode)
- INDEXNODE index hitchhikers
  @ childNode | fromSingletonIndex index
  | Ifz childNode [config newRootNode]
  @ base [config childNode]
  | if (tabIsEmpty hitchhikers) base
  | hmInsertMany hitchhikers base

= (hmLookup key [config r])
| Ifz r NONE
^ _ r
? (lookInNode node)
# case (hmCaseNode node)
- INDEXNODE index hitchhikers
  : v
    < maybeCase (tabLookup key hitchhikers) ( lookInNode
                                            | findSubnodeByKey key index
                                            )
  | (SOME v)
- LEAFNODE items | tabLookup key items

= (hsDeleteItem k _ c) | setDel k c
= (hsEmpty config) | [config 0]
= (hsNull [config r]) | Eqz r
= (hsRawNode [config r]) | r

= (hsCaseNode pinnedNode)
@ !node (PinItem pinnedNode)
| Ifz (1 == Hd node) (LEAFNODE node)
@ [keys nodes hh] node
| INDEXNODE [keys nodes] hh

= (hsRawSingleton v)
| MkPin (setSing v)

(hsSingleton config v)=[config (hsRawSingleton v)]

= hhSetTF
  ++ packIndexNode
  ++ MkPin
  ++ hsCaseNode
  ++ setUnion
  ++ setUnion
  ++ setLen
  ++ setSplitAt
  ++ setMin
  ++ %[]
  ++ hsDeleteItem
  ++ setUnion
  ++ setLen
  ++ setSplitLT
  ++ %[]
  ++ hsDeleteItem

= (hsRawInsert i config r)
@ is | setSing i
| Ifz r | hsRawSingleton i
@ !index | insertRec config hhSetTF is r
@ !fixed | fixup config hhSetTF index
| fixed

(hsInsert i [config r])=[config (hsRawInsert i config r)]

= (hsRawInsertMany set config r)
| if (setIsEmpty set) r
@ TREE_CONFIG(.. ) config
@ !index
  | Ifz r | splitLeafMany hhSetTF maxLeafItems set
  | insertRec config hhSetTF set r
| fixup config hhSetTF index

(hsInsertMany set [config r])=[config (hsRawInsertMany set config r)]

= (hsRawFromSet config c)
| if (setIsEmpty c) NONE
| hsRawInsertMany c config NONE

(hsFromSet config c)=[config (hsRawFromSet config c)]

= (hsToSet [config r])
| Ifz r %[]
| setCatRowAsc
| getLeafRow hhSetTF r

= (hsMember key [config r])
| Ifz r FALSE
^ _ r
? (lookInNode node)
# case (hsCaseNode node)
- INDEXNODE index hitchhikers
  | if (setHas key hitchhikers) TRUE
  | lookInNode | findSubnodeByKey key index
- LEAFNODE items | setHas key items

= (hsRawDelete key config r)
| Ifz r r
@ newRootNode | deleteRec config hhSetTF key NONE r
# case (hsCaseNode newRootNode)
- LEAFNODE leaves | if (setIsEmpty leaves) 0 newRootNode
- INDEXNODE index hitchhikers
  @ childNode | fromSingletonIndex index
  | Ifz childNode newRootNode
  | if (setIsEmpty hitchhikers) childNode
  | hsRawInsertMany hitchhikers config childNode

= (hsDelete key [config r])
@ x | hsRawDelete key config r
[config x]

= (hsRawUnion aconfig ar br)
| Ifz ar br
| Ifz br ar
@ as | setCatRowAsc | getLeafRow hhSetTF ar
@ bs | setCatRowAsc | getLeafRow hhSetTF br
| hsRawFromSet aconfig
| setUnion as bs

= (hsUnion as bs)
@ [aconfig ar] as
@ [_ br] bs
[aconfig (hsRawUnion aconfig ar br)]

=?= 1 | hsNull | hsEmpty twoThreeConfig
=?= 0 | hsNull | hsSingleton twoThreeConfig 9
=?= 0
    | hsNull | hsInsert 8 | hsSingleton twoThreeConfig 9
=?= 0
    | hsNull | hsInsert 9 | hsSingleton twoThreeConfig 9
=?= 1
    | hsNull | hsDelete 9 | hsSingleton twoThreeConfig 9

= (getLeafList treeFun node)
@ TREE_FUN(.. ) treeFun
^ _ hhEmpty node
? (go_openTreeFun hh node)
# case (caseNode node)
- LEAFNODE leaves @ !item (leafInsert leaves hh)
                  | CONS item NIL
- INDEXNODE [keys vals] hitchhikers
  @ !merged (hhMerge hitchhikers hh)
  @ splitHH | splitHitchhikersByKeys treeFun keys merged
  | listCat
  | listMap [hh node]&(go_openTreeFun hh node)
  | listFromRow
  | zip splitHH vals

> List (Set k) > List (Set k) > List (Set k)
= (setlistIntersect ao bo)
| listCase ao NIL
& (a as)
| listCase bo NIL
& (b bs)
@ amin | setMin a
@ amax | setMax a
@ bmin | setMin b
@ bmax | setMax b
@ overlap | and lte-amin-bmax lte-bmin-amax
@ int | setIntersect a b
@ rest
  ^ Br (cmp amax bmax) _ 0
    ++ setlistIntersect as bo
    ++ setlistIntersect as bs
    ++ setlistIntersect ao bs
| if
      | and overlap (not | setIsEmpty int)
  | CONS int rest
rest

=?= ~[]
    | setlistIntersect
    * ~[%[1 2 3] %[4 5 6]]
    * ~[%[7 8 9] %[10 11 12]]

=?= ~[%[6] %[7]]
    | setlistIntersect
    * ~[%[4 5 6] %[7 8 9]]
    * ~[%[6 7]]

=?= ~[%[2] %[4] %[9]]
    | setlistIntersect
    * ~[%[2] %[3] %[4 6] %[9]]
    * ~[%[2] %[4 5] %[7 8 9]]

> Row (HSet k) > List (Set k)
= (hsMultiIntersect setRow)
| Ifz (len setRow) NIL
| if (eql 1 | len setRow)
  @ [_ node] | idx 0 setRow
  | getLeafList hhSetTF node
@ mybNodes | map hsRawNode setRow
| if (any Eqz mybNodes) NIL
@ setNodes | map (getLeafList hhSetTF) mybNodes
^ _ (idx 0 setNodes) 1 (dec (len setNodes))
? (go acc i rem)
| Ifz rem acc
@ rem | dec rem
@ acc | setlistIntersect acc (idx i setNodes)
| Seq acc
| go acc (Inc i) rem

> Nat > List (Set a) > List (Set a)
= (lsDrop num sets)
| Ifz num sets
| listCase sets NIL
& (x xs)
@ xl | setLen x
| if
      | gte num xl
  | lsDrop (sub num xl) xs
| CONS
* setDrop num x
* xs

=?= ~[%[5]] | lsDrop 4 ~[%[1 2 3] %[4 5]]

> Nat > List (Set k) > List (Set k)
= (lsTake num sets)
| Ifz num NIL
| listCase sets NIL
& (x xs)
@ xl | setLen x
| if
      | lth num xl
  | CONS (setTake num x) NIL
| CONS
* x
* lsTake (sub num xl) xs

=?= ~[%[1 2 3]] | lsTake 3 ~[%[1 2 3] %[4 5]]
=?= ~[%[1 2 3] %[4]] | lsTake 4 ~[%[1 2 3] %[4 5]]

> List (Set k) > Nat
= (lsLen sets)
| listFoldl (i s)&(add i | setLen s) 0 sets

=?= 2 | lsLen (CONS %[4] (CONS %[5] NIL))

> List (Set k) > List k
= (lsToList ls)
| listCat
| listMap setToList ls

= (hsmEmpty mapConfig setConfig)
[mapConfig setConfig 0]

= (hsmCaseNode pinnedNode)
@ !node (PinItem pinnedNode)
| Ifz (1 == Hd node) (LEAFNODE node)
@ [keys nodes hh] node
| INDEXNODE [keys nodes] hh

> TreeConfig
  > Tab k (HSet Nat) > Tab k (Set a) > Tab k (HSet Nat)
= (hsmLeafInsertImpl setConfig leaf hh)
@ (alt new m)
  | SOME
  | maybeCase m | hsRawFromSet setConfig new
  & old
  | hsRawInsertMany new setConfig old
@ (merge items k vset) | tabAlter (alt vset) k items
| tabFoldlWithKey merge leaf hh

= (hsmLeafDeleteImpl setConfig k mybV hsm)
| maybeCase mybV (Die %cantDeleteNoValue)
& v
@ (update in)
  | maybeCase in NONE
  & set
  | SOME | hsRawDelete v setConfig set
| tabAlter update k hsm

= (hsmHHDeleteImpl k mybV sm)
| maybeCase mybV (Die %cantDeleteNoValue)
& v
@ (update in) | maybeCase in NONE
              & set
              | SOME | setDel v set
| tabAlter update k sm

(hhSetMapLength a)=(sumOf setLen | tabValsRow a)

= (hhSetMapTF setConfig)
  ++ packIndexNode
  ++ MkPin
  ++ hsmCaseNode
  ++ hsmLeafInsertImpl setConfig
  ++ tabUnionWith (hsRawUnion setConfig)
  ++ tabLen
  ++ tabSplitAt
  ++ tabMinKey
  ++ #[]
  ++ hsmLeafDeleteImpl setConfig
  ++ tabUnionWith setUnion
  ++ hhSetMapLength
  ++ tabSplitLT
  ++ #[]
  ++ hsmHHDeleteImpl

= (hsmInsert k v [mapConfig setConfig r])
| Ifz r
  @ raw | hsRawSingleton v
  @ leaf
        | tabSing k raw
    ++ mapConfig
    ++ setConfig
    ++ MkPin leaf
@ tf | hhSetMapTF setConfig
@ hh | tabSing k (setSing v)
@ !index | insertRec mapConfig tf hh r
@ !fixed
      | fixup mapConfig tf index
  ++ mapConfig
  ++ setConfig
  ++ fixed

= (hsmInsertMany tabset [mapConfig setConfig r])
| if
    | tabIsEmpty tabset
  [mapConfig setConfig r]
@ tf | hhSetMapTF setConfig
@ !index
  | Ifz r
    @ TREE_CONFIG(.. ) mapConfig
    | splitLeafMany tf maxLeafItems
    | tabMapWithKey (k v)&(hsRawFromSet setConfig v) tabset
  | insertRec mapConfig tf tabset r
@ !fixed
      | fixup mapConfig tf index
  ++ mapConfig
  ++ setConfig
  ++ fixed

= (hsmDelete k v [mapConfig setConfig r])
| Ifz r [mapConfig setConfig r]
@ newRootNode
  | deleteRec mapConfig (hhSetMapTF setConfig) k (SOME v) r
# case (hsmCaseNode newRootNode)
- LEAFNODE leaves
  ++ mapConfig
  ++ setConfig
  ++ if (tabIsEmpty leaves) 0 newRootNode
- INDEXNODE index hitchhikers
  @ childNode | fromSingletonIndex index
  | Ifz childNode [mapConfig setConfig newRootNode]
  @ base [mapConfig setConfig childNode]
  | if (tabIsEmpty hitchhikers) base
  | hsmInsertMany hitchhikers base

= (hsmLookup k [mapConfig setConfig r])
@ TREE_CONFIG(.. ) mapConfig
| Ifz r | hsEmpty setConfig
^ _ %[] r
? (lookInNode !hh node)
# case (hsmCaseNode node)
- INDEXNODE children hitchhikers
  @ matched | fromSome %[] (tabLookup k hitchhikers)
  | lookInNode (setUnion hh matched) | findSubnodeByKey k children
- LEAFNODE items
  : ret
    < **maybeCase (tabLookup k items) [setConfig (hsRawFromSet setConfig hh)]
  [setConfig (hsRawInsertMany hh setConfig ret)]

^-^
^-^ HSet HMap HSetMap
^-^ TreeConfig TREE_CONFIG
^-^
^-^
^-^ twoThreeConfig largeConfig
^-^
^-^
^-^ hmEmpty hmSingleton hmSize hmKeys hmInsert hmInsertMany hmDelete hmLookup
^-^
^-^
^-^ hsEmpty hsNull hsSingleton hsInsert hsInsertMany hsDelete hsToSet hsFromSet
^-^ hsMember hsUnion
^-^ hsMultiIntersect
^-^
^-^
^-^ lsDrop lsTake lsLen lsToList
^-^
^-^
^-^ hsmEmpty hsmInsert hsmInsertMany hsmDelete hsmLookup
^-^ tabSplitLT
^-^

