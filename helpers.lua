function table_count(target)
    local count=0;
    for _, _ in pairs(target) do
        count = count + 1;
    end
    return count;
end

function table_stripkeys(target)
    local ret = { };
    for _, v in pairs(target) do
        table.insert(ret,v);
    end
    return ret;
end

function find_by_1(target, f, A, a)
    local ret = { };
    for _, v in pairs(target) do
        if (f(v, A, a)) then
            ret = v;
            break;
        end
    end
    return ret;
end

function find_by_2(target, f, A, B, a, b)
    local ret = { };
    for _, v in pairs(target) do
        if (f(v, A, B, a, b)) then
            ret = v;
            break;
        end
    end
    return ret;
end

function exists_by_1(target, f, A, a)
    local ret = false;

    for _, v in pairs(target) do
        if (f(v, A, a)) then
            ret = true;
            break;
        end
    end

    return ret;
end

function exists_by_2(target, f, A, B, a, b)
    local ret = false;

    for _, v in pairs(target) do
        if (f(v, A, B, a, b)) then
            ret = true;
            break;
        end
    end

    return ret;
end

function filter_by_1(target, f, A, a)
    local ret = { };

    for k, v in pairs(target) do
        if (f(v, A, a)) then
            ret[k] = v;
        end
    end

    return ret;
end

function filter_by_2(target, f, A, B, a, b)
    local ret = { };

    for k, v in pairs(target) do
        if (f(v, A, B, a, b)) then
            ret[k] = v;
        end
    end

    return ret;
end

function test_by_1(v, A, a)
    if v[A] == a then
        return true;
    end
    return false;
end

function test_by_2(v, A, B, a, b)
    if v[A] == a and v[B] == b then
        return true;
    end
    return false;
end

function math.clamp(x, l, h)
    if x < l     then return l;
    elseif x > h then return h;
    else              return x;
    end
end

return {
    table_count     = table_count,
    table_stripkeys = table_stripkeys,
    find_by_1       = find_by_1,
    find_by_2       = find_by_2,
    exists_by_1     = exists_by_1,
    exists_by_2     = exists_by_2,
    filter_by_1     = filter_by_1,
    filter_by_2     = filter_by_2,
    test_by_1       = test_by_1,
    test_by_2       = test_by_2
}