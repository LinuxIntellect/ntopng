--
-- (C) 2020 - ntop.org
--

local json = require("dkjson")

local MAX_POSTS = 3
local blog_utils = {}

-- Parse the date string, following this pattern: yyyy-mm-ddTH:M:S+00:00
-- Return 0 if the date string is empty, otherwise it returns the right epoch
function blog_utils.parseDate(date)

    if (isEmptyString(date)) then return 0 end

    local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)+(%d+):(%d+)"
    local year, month, day, hour, minutes = date:match(pattern)

    local epoch = os.time({year=year, month=month, day=day, hour=hour, min=minutes})
    return epoch
end

function blog_utils.intersectPosts(s1, s2)

    -- if there aren't any old post then return the new ones
    if (s1[1] == nil) then return s2 end
    -- do integrity check on old set
    if (s1[1].epoch == nil) then return s2 end
    -- if there aren't any new post then return the old ones
    if (s2[1] == nil) then return s1 end

    local intersected = {}
    local firstOlderPost = s1[1]
    local j = 1

    -- insert the new posts
    for i = 1, MAX_POSTS do
        if (firstOlderPost.epoch < s2[i].epoch) then
            intersected[i] = s2[i]
            j = j + 1
        end
    end

    -- insert the olds posts if the array is not full
    for i = j, MAX_POSTS do
        intersected[i] = s1[i]
    end

    return (intersected)

end

function blog_utils.updatePostState(blogNotificationId, username)

    if (blogNotificationId == nil) then return false end
    if (isEmptyString(username)) then return false end

    local postsJSON = ntop.getPref("ntopng.prefs.blog_feed")
    local posts = {}

    if (not isEmptyString(postsJSON)) then
        posts = json.decode(postsJSON)
    end

    local success = false

    for _, p in pairs(posts) do
        if (p.id == blogNotificationId) then
            if (p.users_read == nil) then p.users_read = {} end
            p.users_read[username] = true
            success = true
        end
    end

    ntop.setPref("ntopng.prefs.blog_feed", json.encode(posts))

    return (success)
end

function blog_utils.updateRedis(newPosts)

    -- decode older posts from updateRedis
    local oldPostsJSON = ntop.getPref("ntopng.prefs.blog_feed")
    local oldPosts = {}
    if (not isEmptyString(oldPostsJSON)) then
        oldPosts = json.decode(oldPostsJSON)
    end

    -- intersect two notifications sets and marks the new
    local intersected = blog_utils.intersectPosts(oldPosts, newPosts)

    -- save the posts inside redis
    ntop.setPref("ntopng.prefs.blog_feed", json.encode(intersected))

end

function blog_utils.fetchLatestPosts()

    local JSON_FEED = "https://www.ntop.org/blog/feed/json"
    local response = ntop.httpGet(JSON_FEED)

    if ((response == nil) or (response["CONTENT"] == nil)) then
        return (false)
    end

    local jsonFeed = json.decode(response["CONTENT"])

    if ((jsonFeed == nil) or table.empty(jsonFeed["items"])) then
        return (false)
    end

    local posts = jsonFeed["items"]

    local latest3Posts = {posts[1], posts[2], posts[3]}
    local formattedPosts = {}

    for i, post in ipairs(latest3Posts) do

        if (post ~= nil) then

            local splittedLink = split(post.id, "?p=")
            local postId = tonumber(splittedLink[2])
            local postTitle = post.title
            local postURL = post.url
            local postShortDesc = string.sub(post.content_text, 1, 48) .. '...'
            local postEpoch = blog_utils.parseDate(post.date_published)

            local post = {
                id = postId,
                title = postTitle,
                link = postURL,
                shortDesc = postShortDesc,
                epoch = postEpoch
            }

            table.insert(formattedPosts, post)
        end
    end

    -- updates redis
    blog_utils.updateRedis(formattedPosts)

    return (true)
end

function blog_utils.readPostsFromRedis(username)

    if (username == nil) then return {} end
    if (isEmptyString(username)) then return {} end

    local postsJSON = ntop.getPref("ntopng.prefs.blog_feed")
    local posts = {}

    if (not isEmptyString(postsJSON)) then
        posts = json.decode(postsJSON)
    end

    local newPostCounter = 0

    -- post.users_read is an array which contains
    -- the users who read the notification
    for _, post in pairs(posts) do
        if (post.users_read == nil) then
            post.users_read = {}
            newPostCounter = newPostCounter + 1
        else
            if (not post.users_read[username]) then
                newPostCounter = newPostCounter + 1
            end
        end
    end

    return posts, newPostCounter
end

return blog_utils
