require "sinatra"
require "sinatra/namespace"
require_relative 'models.rb'
require_relative "api_authentication.rb"
require "json"
require 'fog'
require 'csv'
require 'httparty'

connection = Fog::Storage.new({
:provider                 => 'AWS',
:aws_access_key_id        => 'youraccesskey',
:aws_secret_access_key    => 'yoursecretaccesskey'
})

if ENV['DATABASE_URL']
	S3_BUCKET = "instagram"
else
	S3_BUCKET = "instagram-dev"
end

def placeholder
	halt 501, {message: "Not Implemented"}.to_json
end

if !User.first(email: "student@student.com")
	u = User.new
	u.email = "student@student.com"
	u.password = "student"
	u.bio = "Student"
	u.profile_image_url = "https://via.placeholder.com/1080.jpg"
	u.save
end

namespace '/api/v1' do
	before do
		content_type 'application/json'
	end

	#ACCOUNT MAINTENANCE

	#returns JSON representing the currently logged in user
	get "/my_account" do
		api_authenticate!
		halt 200, current_user.to_json(exclude:[:password ,:role_id])
	end
	#let people update their bio
	patch "/my_account" do
		api_authenticate!
		if(params["bio"]) 
			current_user.bio = params["bio"]
			current_user.save
		end
	end

	#let people update their profile image
	patch "/my_account/profile_image" do
		api_authenticate!
			if params[:image] && params[:image][:tempfile] && params[:image][:filename]
           	 begin
                token = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo2OH0.3DOj4iAzAy84QhAuEQdKM07i5izvNVMFDLECzpNySbo"
                file = params[:image][:tempfile]
                response = HTTParty.post("http://nameless-forest-80107.herokuapp.com/api/images", body: { image: file },  :headers => { "Authorization" => token} )
                data = JSON.parse(response.body) 
 
                #make post
                current_user.profile_image_url = data["url"]
                current_user.save
                halt 200, {"message" => "Image updated"}.to_json
           	 rescue => e
                puts e.message
                halt 422, {message: "Unable to create image"}.to_json
				end 	
			end
	end

	#returns JSON representing all the posts by the current user
	#returns 404 if user not found
	get "/my_posts" do
		api_authenticate!
		p = Post.all(user_id: current_user.id)
		if (p)
			halt 200,p.to_json
		else
			halt 404,{message: "User Not Found"}.to_json
		end

	end


	#USERS

	#returns JSON reprsenting the user with the given id
	#returns 404 if user not found
	get "/users/:id" do
		api_authenticate!
			x = params[:id]
			u = User.get(x)
		if(u)
			halt 200,u.to_json(exclude:[:password,:role_id])
		else
			halt 404,{Message: "User not found"}.to_json
		end
			
	end

	#returns JSON representing all the posts by the user with the given id
	#returns 404 if user not found
	get "/users/:user_id/posts" do
		api_authenticate!
			user_p = Post.get(params[:user_id])
			halt 200,user_p.to_json
			
	end

	# POSTS

	#returns JSON representing all the posts in the database
	get "/posts" do
		api_authenticate!
			post = Post.all
			halt 200,post.to_json
	end

	#returns JSON representing the post with the given id
	#returns 404 if post not found
	get "/posts/:id" do
		api_authenticate!
			post = Post.get(params[:id])
			if(post != nil)
				halt 200, post.to_json
			else 
		 		halt 404,{Message: "post not found"}.to_json
			end
	end

	#adds a new post to the database
	#must accept "caption" and "image" parameters
	post "/posts" do
		api_authenticate!
		if (params[:image] && params[:caption])
			begin
			token = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo2OH0.3DOj4iAzAy84QhAuEQdKM07i5izvNVMFDLECzpNySbo"
			file = params[:image][:tempfile]
			response = HTTParty.post("http://nameless-forest-80107.herokuapp.com/api/images", body: { image: file },  :headers => { "Authorization" => token} )
			data = JSON.parse(response.body) 

			#make post
			p = Post.new
			p.caption = params["caption"]
			p.image_url = data["url"]
			p.user_id = current_user.id
			p.save

			halt 200, {"message" => "Image updated"}.to_json
			rescue => e
			puts e.message
			halt 422, {message: "Unable to create image"}.to_json
			end 	
		end
	end

	#updates the post with the given ID
	#only allow updating the caption, not the image
	patch "/posts/:id" do
		api_authenticate!
			post = Post.get(params[:id])

			if(post != nil)
				caption = params["caption"]
	
				if( caption == nil)
					halt 422, {message: "Missing parameters to update"}.to_json
				end
	
				if(caption != nil)
					post.caption = caption
				end
	
				post.save
	
				halt 200, post.to_json
	
			else
				halt 404, {message: "Post not found"}.to_json
			end
	end

	#deletes the post with the given ID
	#returns 404 if post not found
	delete "/posts/:id" do
		api_authenticate!
			p = Post.get(params["id"])
				if (p != nil)
					if (current_user.id == p.user_id)	
						p.destroy
						halt 200,{message: "Post Deleted"}.to_json
					else
						halt 401,{message: "Not Authorized"}.to_json
					end
				else
					halt 404,{message: "Post not found"}.to_json
				end
				
	end

	#COMMENTS

	#returns JSON representing all the comments
	#for the post with the given ID
	#returns 404 if post not found
	get "/posts/:id/comments" do
		api_authenticate!
			p = Post.get(:id)
			post_id = p.id
			if(p != nil)
				c = Comment.get(post_id)
				halt 200,c.to_json
			else
				halt 404,{Message: "Post not found"}.to_json
			end
	end

	#adds a comment to the post with the given ID
	#accepts "text" parameter
	#returns 404 if post not found
	post "/posts/:id/comments" do
		api_authenticate!
			p = Post.get(params["id"])
			postid = p.id
			if (p == nil)
				halt 404,{message: "Post not found"}.to_json
			end
			if(current_user.id == p.user_id)
				if(params["text"])
					c = Comment.new
					c.post_id = postid
					c.user_id = current_user.id
					c.text = params["text"]
					c.save
				end
			end

	end

	#updates the comment with the given ID
	#only allows updating "text" property
	#returns 404 if not found
	#returns 401 if comment does not belong to current user
	patch "/comments/:id" do
		api_authenticate!
			com = Comment.get(params["id"])
			if (com == nil)
				halt 404,{message: "comment not found"}.to_json
			end
			if(com.user_id != current_user.id)
				halt 401,{message: "comment does not belong to user"}.to_json
			end
			if (params["text"] != nil)
					com.text = params["text"] 
					com.save
					halt 200,com.to_json
			end

	end

	#deletes the comment with the given ID
	#returns 404 if not found
	#returns 401 if comment does not belong to current user
	delete "/comments/:id" do
		api_authenticate!
			c = Comment.get(params["id"])
			if(c != nil)
				if(current_user.id == c.user_id)
					c.destroy
					halt 200,{Message: "Comment Deleted"}.to_json
				else
					halt 401,{Message: "Comment does not belong to current user"}.to_json
				end
			else
				halt 404,{Message: "Not found"}.to_json
			end
	end

	#LIKES
	
	#get the likes for the post with the given ID
	#returns 404 if post not found
	get "/posts/:id/likes" do
		api_authenticate!
			post = Post.get(:id)
			like = Like.get(p.id)

			if(post && like)
				halt 200,like.to_json
			else
				halt 404,{message: "Post not found"}.to_json
			end
	end

	#adds a like to a post, if not already liked
	#returns 404 if post not found
	post "/posts/:id/likes" do
		api_authenticate!
		post = Post.get(params["id"])
		like = Like.get(post_id: post.id)
			if(post == nil)
				halt 404, {message: "post not found"}.to_json
			end

			if (like != nil)
				halt 200,{message: "This is already liked"}.to_json
			else
				newlike = Like.new
				newlike.post_id = post.id
				newlike.user_id = current_user.id
				newlike.save
				halt 201,{message: "Like created"}.to_json
			end
		
	end

	#deletes a like from the post with
	#the given ID, if the like exists
	#returns 404 if not found
	#returns 401 if like does not belong to current user
	delete "/posts/:id/likes" do
		api_authenticate!
		post = Post.get(params[:id])
		like = Like.get(post.id)
			if(like && post)
				if(current_user.id == like.user_id)
					like.destroy
					halt 200,{Message: "Like Deleted"}.to_json
				else
					halt 401,{Message: "Like does not belong to current user"}.to_json
				end
			else
				halt 404,{Message: "Not found"}.to_json
			end
	end
end
