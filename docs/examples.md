# Promise Integration Examples

## Promisify & Retry Pattern

```luau
local Promise = require(path.to.Promise)

local function unsafeNetworkCall(id: number)
    if math.random() < 0.5 then error("Network error") end
    return "Data_" .. tostring(id)
end

local safeFetch = Promise.promisify(unsafeNetworkCall)

Promise.retryWithDelay(function()
    return safeFetch(42)
end, 3, 1):andThen(function(result)
    print("Fetch succeeded:", result)
end):catch(function(err)
    warn("Fetch failed after retries:", err)
end)
```

## Hash & Timeout Combinators

```luau
local Promise = require(path.to.Promise)

Promise.hash({
    playerData = Promise.delay(0.5):andThen(function() return { coins = 100 } end),
    inventory  = Promise.delay(0.2):andThen(function() return { "Sword", "Shield" } end),
}):timeout(2.0):andThen(function(results)
    print("Coins:", results.playerData.coins)
    print("Inventory count:", #results.inventory)
end):expect()
```
